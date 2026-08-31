#!/bin/bash

set -e

# ============================================================
# Validate arguments
# ============================================================

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GNB_DIR="$PROJECT_ROOT/build/gnb-${INSTANCE}"
UE_DIR="$PROJECT_ROOT/build/ue-${INSTANCE}"

OAM_CREATE_SCRIPT="$PROJECT_ROOT/scripts/networks/OAM/create-oam-network.sh"
OAM_CONNECT_SCRIPT="$PROJECT_ROOT/scripts/networks/OAM/connect-oam.sh"

# ============================================================
# Validate instance
# ============================================================

if [ ! -d "$GNB_DIR" ]; then
    echo "Error: gNB instance ${INSTANCE} does not exist."
    echo "Expected: ${GNB_DIR}"
    exit 1
fi

if [ ! -d "$UE_DIR" ]; then
    echo "Error: UE instance ${INSTANCE} does not exist."
    echo "Expected: ${UE_DIR}"
    exit 1
fi

# ============================================================
# Validate OAM scripts
# ============================================================

if [ ! -x "$OAM_CREATE_SCRIPT" ]; then
    echo "Error: OAM creation script not found or not executable:"
    echo "  $OAM_CREATE_SCRIPT"
    exit 1
fi

if [ ! -x "$OAM_CONNECT_SCRIPT" ]; then
    echo "Error: OAM connection script not found or not executable:"
    echo "  $OAM_CONNECT_SCRIPT"
    exit 1
fi

# ============================================================
# Start instance
# ============================================================

echo "=============================================="
echo " Starting instance ${INSTANCE}"
echo "=============================================="
echo

# ============================================================
# OAM network
# ============================================================

echo "Checking OAM network..."

if docker network inspect "OAM-${INSTANCE}" >/dev/null 2>&1; then
    echo "OAM-${INSTANCE} already exists."
else
    echo "Creating OAM network..."
    "$OAM_CREATE_SCRIPT" "$INSTANCE"
fi

echo

# ============================================================
# gNB
# ============================================================

echo "Starting gNB..."

docker compose -f "$GNB_DIR/compose.yaml" up -d

echo

# ============================================================
# Connect gNB to OAM
# ============================================================

echo "Connecting gNB to OAM..."

"$OAM_CONNECT_SCRIPT" "$INSTANCE"

echo

# ============================================================
# UE
# ============================================================

echo "Starting UE..."

docker compose -f "$UE_DIR/compose.yaml" up -d

echo

# ============================================================
# Finished
# ============================================================

echo "=============================================="
echo " Instance ${INSTANCE} started successfully"
echo "=============================================="
echo

echo "Containers:"

docker ps \
    --filter "name=nr_gnb_${INSTANCE}" \
    --filter "name=nr_ue_${INSTANCE}" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"