#!/usr/bin/env bash

set -uo pipefail

# ============================================================
# Test 1 - Continuous Container Resource Logger
#
# Usage:
#   ./test.sh
#
# The experiment configuration is read from:
#   ../current_experiment
#
# Results are appended to:
#   ../results/metrics.csv
#
# This script does NOT manage the deployment.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$EXPERIMENTS_DIR/.." && pwd)"

STATE_FILE="$EXPERIMENTS_DIR/current_experiment"
OUTPUT_FILE="$EXPERIMENTS_DIR/results/metrics.csv"

SAMPLE_INTERVAL=1

declare -A DISCOVERED_CONTAINERS=()


# ============================================================
# Validation
# ============================================================

if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: Experiment state file does not exist:"
    echo "       $STATE_FILE"
    exit 1
fi

if [[ ! -d "$EXPERIMENTS_DIR/results" ]]; then
    echo "ERROR: Results directory does not exist:"
    echo "       $EXPERIMENTS_DIR/results"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker command not found."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not accessible."
    exit 1
fi


# ============================================================
# Read experiment configuration
# ============================================================

read_experiment_state() {

    local experiment
    local towers
    local shared_ledgers

    experiment="$(grep '^experiment=' "$STATE_FILE" | cut -d= -f2)"
    towers="$(grep '^towers=' "$STATE_FILE" | cut -d= -f2)"
    shared_ledgers="$(grep '^shared_ledgers=' "$STATE_FILE" | cut -d= -f2)"

    if [[ -z "$experiment" || -z "$towers" || -z "$shared_ledgers" ]]; then
        echo "ERROR: Invalid experiment state file:"
        cat "$STATE_FILE"
        exit 1
    fi

    CURRENT_EXPERIMENT="$experiment"
    CURRENT_TOWERS="$towers"
    CURRENT_LEDGERS="$shared_ledgers"
}


# ============================================================
# Convert Docker byte values to bytes
# ============================================================

to_bytes() {

    local value="$1"

    value="${value// /}"

    if [[ -z "$value" || "$value" == "-" ]]; then
        echo "0"
        return
    fi

    local number
    local unit

    number="$(echo "$value" | sed -E 's/^([0-9.]+).*/\1/')"
    unit="$(echo "$value" | sed -E 's/^[0-9.]+(.*)$/\1/')"

    awk -v n="$number" -v u="$unit" '
        BEGIN {

            multiplier = 1

            if (u == "kB")       multiplier = 1000
            else if (u == "MB")  multiplier = 1000^2
            else if (u == "GB")  multiplier = 1000^3
            else if (u == "TB")  multiplier = 1000^4

            else if (u == "KiB") multiplier = 1024
            else if (u == "MiB") multiplier = 1024^2
            else if (u == "GiB") multiplier = 1024^3
            else if (u == "TiB") multiplier = 1024^4

            printf "%.0f", n * multiplier
        }
    '
}


# ============================================================
# Discover prototype containers
# ============================================================

discover_containers() {

    while IFS=$'\t' read -r name working_dir; do

        if [[ -n "$working_dir" &&
              "$working_dir" == "$PROJECT_ROOT"/* ]]; then

            DISCOVERED_CONTAINERS["$name"]=1

        fi

    done < <(
        docker ps \
            --format '{{.Names}}\t{{.Label "com.docker.compose.project.working_dir"}}'
    )


    # Fabric development chaincode containers do not have
    # Compose labels.

    while read -r name; do

        [[ -z "$name" ]] && continue

        DISCOVERED_CONTAINERS["$name"]=1

    done < <(
        docker ps --format '{{.Names}}' |
        grep '^dev-fabric-peer-[0-9].*-logging_' || true
    )
}


# ============================================================
# Collect one sample
# ============================================================

collect_sample() {

    local timestamp="$1"

    docker stats \
        --no-stream \
        --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' |
    while IFS='|' read -r NAME CPU MEM NET BLOCK; do

        if [[ -z "${DISCOVERED_CONTAINERS[$NAME]+x}" ]]; then
            continue
        fi


        # CPU

        CPU="${CPU%\%}"


        # Memory

        MEM_USED="${MEM%% / *}"
        MEMORY_BYTES="$(to_bytes "$MEM_USED")"


        # Network I/O

        NET_RX="${NET%% / *}"
        NET_TX="${NET##* / }"

        NET_RX_BYTES="$(to_bytes "$NET_RX")"
        NET_TX_BYTES="$(to_bytes "$NET_TX")"


        # Block I/O

        BLOCK_READ="${BLOCK%% / *}"
        BLOCK_WRITE="${BLOCK##* / }"

        BLOCK_READ_BYTES="$(to_bytes "$BLOCK_READ")"
        BLOCK_WRITE_BYTES="$(to_bytes "$BLOCK_WRITE")"


        echo "$timestamp,$CURRENT_EXPERIMENT,$CURRENT_TOWERS,$CURRENT_LEDGERS,$NAME,$CPU,$MEMORY_BYTES,$NET_RX_BYTES,$NET_TX_BYTES,$BLOCK_READ_BYTES,$BLOCK_WRITE_BYTES" \
            >> "$OUTPUT_FILE"

    done
}


# ============================================================
# CSV initialization
# ============================================================

if [[ ! -f "$OUTPUT_FILE" ]]; then

    echo "timestamp,experiment,towers,shared_ledgers,container,cpu_percent,memory_bytes,network_rx_bytes,network_tx_bytes,block_read_bytes,block_write_bytes" \
        > "$OUTPUT_FILE"

fi


# ============================================================
# Shutdown
# ============================================================

cleanup() {

    echo
    echo "=============================================="
    echo " Test 1 stopped"
    echo "=============================================="
    echo
    echo "Results:"
    echo "  $OUTPUT_FILE"
    echo

    exit 0
}

trap cleanup INT TERM


# ============================================================
# Startup
# ============================================================

read_experiment_state

echo
echo "=============================================="
echo " Test 1 - Container Resource Logger"
echo "=============================================="
echo
echo "Experiment     : $CURRENT_EXPERIMENT"
echo "Towers         : $CURRENT_TOWERS"
echo "Shared ledgers : $CURRENT_LEDGERS"
echo "Sample interval: ${SAMPLE_INTERVAL}s"
echo
echo "State file:"
echo "  $STATE_FILE"
echo
echo "Output file:"
echo "  $OUTPUT_FILE"
echo
echo "Logger running..."
echo "Press Ctrl+C to stop."
echo
echo "=============================================="
echo


# ============================================================
# Main loop
# ============================================================

while true; do

    # --------------------------------------------------------
    # Reload experiment state.
    #
    # This allows the automation to change experiments without
    # restarting the logger.
    # --------------------------------------------------------

    read_experiment_state


    # --------------------------------------------------------
    # Discover newly started containers.
    # --------------------------------------------------------

    BEFORE_COUNT="${#DISCOVERED_CONTAINERS[@]}"

    discover_containers

    AFTER_COUNT="${#DISCOVERED_CONTAINERS[@]}"


    if [[ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ]]; then

        echo "[$(date '+%H:%M:%S')] Containers discovered: $AFTER_COUNT"

    fi


    # --------------------------------------------------------
    # Collect metrics.
    # --------------------------------------------------------

    TIMESTAMP="$(date --iso-8601=seconds)"

    collect_sample "$TIMESTAMP"


    sleep "$SAMPLE_INTERVAL"

done