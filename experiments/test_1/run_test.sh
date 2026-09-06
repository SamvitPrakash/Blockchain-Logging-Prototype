#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STATE_FILE="$SCRIPT_DIR/../current_experiment"
GENERATE_SCRIPT="$PROJECT_ROOT/scripts/generate.sh"

SETTLE_TIME=60
POLL_INTERVAL=1

HANDSHAKE_MESSAGE='\"message\":\"PDU session resource(s) setup for UE[1] count[1]\"'


usage() {
    echo "Usage:"
    echo "  sudo $0 <towers> <shared_ledgers> <seed> <experiment_number>"
    echo
    echo "Example:"
    echo "  sudo $0 2 1 12345 1"
    exit 1
}


write_experiment_state() {
    local towers="$1"
    local shared_ledgers="$2"
    local experiment_number="$3"

    local temp_file
    temp_file="$(mktemp "${STATE_FILE}.XXXXXX")"

    cat > "$temp_file" <<EOF
experiment=$experiment_number
towers=$towers
shared_ledgers=$shared_ledgers
EOF

    mv "$temp_file" "$STATE_FILE"
}


wait_for_final_vnf() {
    local towers="$1"
    local deployment_start="$2"

    local final_vnf="vnf-${towers}"

    echo
    echo "Waiting for final VNF: $final_vnf"
    echo
    echo "Completion message:"
    echo "  $HANDSHAKE_MESSAGE"
    echo

    while true; do

        logs="$(docker logs "$final_vnf" 2>&1 || true)"

        if grep -Fq "$HANDSHAKE_MESSAGE" <<< "$logs"; then
            echo
            echo "=============================================="
            echo " Deployment complete"
            echo "=============================================="
            echo
            echo "Final VNF : $final_vnf"
            echo "Handshake : detected"
            echo

            return 0
        fi
        
        sleep "$POLL_INTERVAL"
    done
}


main() {

    if [[ $# -ne 4 ]]; then
        usage
    fi

    local towers="$1"
    local shared_ledgers="$2"
    local seed="$3"
    local experiment_number="$4"

    if [[ ! "$towers" =~ ^[0-9]+$ ]] || (( towers < 1 )); then
        echo "ERROR: Invalid number of towers: $towers"
        exit 1
    fi

    if [[ ! "$shared_ledgers" =~ ^[0-9]+$ ]] ||
       (( shared_ledgers < 1 )); then
        echo "ERROR: Invalid number of shared ledgers: $shared_ledgers"
        exit 1
    fi

    if (( shared_ledgers > towers )); then
        echo "ERROR: Shared ledgers cannot exceed number of towers."
        exit 1
    fi

    if [[ ! -x "$GENERATE_SCRIPT" ]]; then
        echo "ERROR: Generate script not found or not executable:"
        echo "  $GENERATE_SCRIPT"
        exit 1
    fi

    echo "=============================================="
    echo " Deployment Automation"
    echo "=============================================="
    echo
    echo "Towers         : $towers"
    echo "Shared ledgers : $shared_ledgers"
    echo "Seed           : $seed"
    echo "Settle time    : ${SETTLE_TIME}s"
    echo "Experiment number: $experiment_number"
    echo

    write_experiment_state "$towers" "$shared_ledgers" "$experiment_number"

    echo "Experiment state updated."
    echo

    local deployment_start
    deployment_start="$(date +%s)"

    echo "Starting deployment..."
    echo

    sudo "$GENERATE_SCRIPT" \
        "$towers" \
        "$shared_ledgers" \
        "$seed"

    wait_for_final_vnf \
        "$towers" \
        "$deployment_start"

    echo "Allowing system to settle for ${SETTLE_TIME} seconds..."
    echo "Test 1 will continue collecting measurements."
    echo

    sleep "$SETTLE_TIME"

    echo
    echo "=============================================="
    echo " Deployment experiment complete"
    echo "=============================================="
    echo
}


main "$@"