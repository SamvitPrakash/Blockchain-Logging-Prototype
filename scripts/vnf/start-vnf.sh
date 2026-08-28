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

VNF_DIR="$PROJECT_ROOT/build/vnf-${INSTANCE}"

# ============================================================
# Validate VNF instance
# ============================================================

if [ ! -d "$VNF_DIR" ]; then
    echo "Error: VNF instance ${INSTANCE} does not exist."
    echo "Expected: ${VNF_DIR}"
    exit 1
fi

if [ ! -f "$VNF_DIR/compose.yaml" ]; then
    echo "Error: VNF Compose file not found:"
    echo "  $VNF_DIR/compose.yaml"
    exit 1
fi

# ============================================================
# Validate networks
# ============================================================

if ! docker network inspect "OAM-${INSTANCE}" >/dev/null 2>&1; then
    echo "Error: OAM-${INSTANCE} does not exist."
    echo
    echo "Create it with:"
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    exit 1
fi

if ! docker network inspect XIT >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo
    echo "Create it with:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

# ============================================================
# Start VNF
# ============================================================

echo "=============================================="
echo " Starting VNF instance ${INSTANCE}"
echo "=============================================="
echo

docker compose -f "$VNF_DIR/compose.yaml" up -d

echo

# ============================================================
# Display network configuration
# ============================================================

echo "=============================================="
echo " VNF instance ${INSTANCE} started"
echo "=============================================="
echo

docker inspect "vnf_${INSTANCE}" \
    --format='{{range $name, $network := .NetworkSettings.Networks}}{{$name}} : {{$network.IPAddress}}{{println}}{{end}}'