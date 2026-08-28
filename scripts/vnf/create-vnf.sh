#!/bin/bash

set -e

# ============================================================
# VNF Instance Generator
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

BUILD_DIR="$PROJECT_ROOT/build"
VNF_TEMPLATE="$PROJECT_ROOT/templates/vnf/compose.yaml"
VNF_BUILD_DIR="$BUILD_DIR/vnf-${INSTANCE}"

# ============================================================
# Instance configuration
# ============================================================

VNF_CONTAINER="vnf_${INSTANCE}"

OAM_NETWORK="OAM-${INSTANCE}"

VNF_OAM_IP="10.20.${INSTANCE}.3"

VNF_XIT_IP="10.10.0.$((INSTANCE + 1))"

VNF_PORT="5000"

VNF_PEERS=""

# ============================================================
# Validate template
# ============================================================

if [ ! -f "$VNF_TEMPLATE" ]; then
    echo "Error: VNF template not found:"
    echo "  $VNF_TEMPLATE"
    exit 1
fi

# ============================================================
# Check OAM network
# ============================================================

if ! docker network inspect "$OAM_NETWORK" >/dev/null 2>&1; then
    echo "Error: OAM network '${OAM_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    exit 1
fi

# ============================================================
# Check XIT network
# ============================================================

if ! docker network inspect XIT >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo
    echo "Create it first with:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

# ============================================================
# Check for duplicate instance
# ============================================================

if [ -d "$VNF_BUILD_DIR" ]; then
    echo "Error: VNF instance ${INSTANCE} already exists."
    echo
    echo "Existing directory:"
    echo "  $VNF_BUILD_DIR"
    exit 1
fi

# ============================================================
# Discover existing VNF peers
# ============================================================

VNF_PEERS=""

for VNF_DIR in "$BUILD_DIR"/vnf-*; do

    [ -d "$VNF_DIR" ] || continue

    PEER_INSTANCE="${VNF_DIR##*-}"

    # Ignore the instance currently being created
    if [ "$PEER_INSTANCE" = "$INSTANCE" ]; then
        continue
    fi

    # Only consider numeric VNF directories
    if ! [[ "$PEER_INSTANCE" =~ ^[0-9]+$ ]]; then
        continue
    fi

    PEER_IP="10.10.0.$((PEER_INSTANCE + 1))"

    if [ -z "$VNF_PEERS" ]; then
        VNF_PEERS="$PEER_IP"
    else
        VNF_PEERS="${VNF_PEERS},${PEER_IP}"
    fi

done

# ============================================================
# Create build directory
# ============================================================

mkdir -p "$VNF_BUILD_DIR"

# ============================================================
# Generate Docker Compose
# ============================================================

export VNF_CONTAINER
export OAM_NETWORK
export VNF_OAM_IP
export VNF_XIT_IP
export VNF_PORT
export VNF_PEERS

envsubst < "$VNF_TEMPLATE" \
    > "$VNF_BUILD_DIR/compose.yaml"

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNF instance ${INSTANCE} created successfully"
echo "=============================================="
echo

echo "Container:"
echo "  ${VNF_CONTAINER}"

echo

echo "OAM:"
echo "  Network : ${OAM_NETWORK}"
echo "  IP      : ${VNF_OAM_IP}"

echo

echo "XIT:"
echo "  Network : XIT"
echo "  IP      : ${VNF_XIT_IP}"

echo

echo "VNF:"
echo "  Port    : ${VNF_PORT}"
echo "  Peers   : ${VNF_PEERS:-none}"

echo

echo "Generated:"
echo "  ${VNF_BUILD_DIR}/compose.yaml"