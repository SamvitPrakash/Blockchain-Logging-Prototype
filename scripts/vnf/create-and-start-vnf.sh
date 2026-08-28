#!/bin/bash

set -e

# ============================================================
# VNF Create and Start
# ============================================================

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <number-of-instances>"
    exit 1
fi

COUNT="$1"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
    echo "Error: number of instances must be a positive integer."
    exit 1
fi

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CREATE_VNF="$SCRIPT_DIR/create-vnf.sh"
START_VNF="$SCRIPT_DIR/start-vnf.sh"

# ============================================================
# Validate scripts
# ============================================================

if [ ! -x "$CREATE_VNF" ]; then
    echo "Error: create-vnf.sh is missing or not executable."
    exit 1
fi

if [ ! -x "$START_VNF" ]; then
    echo "Error: start-vnf.sh is missing or not executable."
    exit 1
fi

# ============================================================
# XIT network
# ============================================================

if ! docker network inspect XIT >/dev/null 2>&1; then
    echo "Creating XIT network..."
    "$PROJECT_ROOT/scripts/networks/XIT/setup-XIT.sh"
else
    echo "XIT network already exists."
fi

# ============================================================
# Create VNF instances
# ============================================================

echo
echo "=============================================="
echo " Creating ${COUNT} VNF instances"
echo "=============================================="

for INSTANCE in $(seq 1 "$COUNT"); do

    echo
    echo "Creating VNF ${INSTANCE}..."

    "$CREATE_VNF" "$INSTANCE"

done

# ============================================================
# Configure VNF peer relationships
# ============================================================

echo
echo "=============================================="
echo " Configuring VNF peer relationships"
echo "=============================================="

for INSTANCE in $(seq 1 "$COUNT"); do

    VNF_DIR="$PROJECT_ROOT/build/vnf-${INSTANCE}"
    COMPOSE_FILE="$VNF_DIR/compose.yaml"

    PEERS=""

    for PEER in $(seq 1 "$COUNT"); do

        if [ "$PEER" -eq "$INSTANCE" ]; then
            continue
        fi

        PEER_IP="10.10.0.$((PEER + 1))"

        if [ -z "$PEERS" ]; then
            PEERS="$PEER_IP"
        else
            PEERS="${PEERS},${PEER_IP}"
        fi

    done

    echo
    echo "VNF ${INSTANCE}"
    echo "  Peers : ${PEERS:-none}"

    sed -i \
        "s|VNF_PEERS: \".*\"|VNF_PEERS: \"${PEERS}\"|" \
        "$COMPOSE_FILE"

done

# ============================================================
# Start VNF instances
# ============================================================

echo
echo "=============================================="
echo " Starting ${COUNT} VNF instances"
echo "=============================================="

for INSTANCE in $(seq 1 "$COUNT"); do

    echo
    echo "Starting VNF ${INSTANCE}..."

    "$START_VNF" "$INSTANCE"

done

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " All ${COUNT} VNF instances started"
echo "=============================================="
echo

docker ps \
    --filter "name=vnf_" \
    --format "table {{.Names}}\t{{.Status}}"