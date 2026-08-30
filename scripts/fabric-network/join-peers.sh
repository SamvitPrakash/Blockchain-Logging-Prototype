#!/bin/bash

set -euo pipefail

# ============================================================
# Fabric Peer Channel Join
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

BUILD_DIR="$PROJECT_ROOT/build/fabric-network"

TOPOLOGY_FILE="$BUILD_DIR/topology.json"
CHANNEL_DIR="$BUILD_DIR/channels"

FABRIC_TOOLS_IMAGE="hyperledger/fabric-tools:2.5.16"

XIT_NETWORK="XIT"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TOPOLOGY_FILE" ]; then
    echo "Error: topology.json does not exist:"
    echo "  $TOPOLOGY_FILE"
    exit 1
fi

if [ ! -d "$CHANNEL_DIR" ]; then
    echo "Error: channel directory does not exist:"
    echo "  $CHANNEL_DIR"
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: Docker network '${XIT_NETWORK}' does not exist."
    exit 1
fi

# ============================================================
# Read topology
# ============================================================

TOPOLOGY_JSON="$(docker run --rm \
    -v "$TOPOLOGY_FILE:/topology.json:ro" \
    "$FABRIC_TOOLS_IMAGE" \
    sh -c 'cat /topology.json')"

# ============================================================
# Extract peer/channel assignments
# ============================================================

mapfile -t ASSIGNMENTS < <(
    printf '%s\n' "$TOPOLOGY_JSON" |
    docker run --rm -i \
        "$FABRIC_TOOLS_IMAGE" \
        jq -r '
            .channels
            | to_entries[]
            | .key as $channel
            | .value[]
            | "\(.):\($channel)"
        '
)

if [ "${#ASSIGNMENTS[@]}" -eq 0 ]; then
    echo "Error: no peer/channel assignments found in:"
    echo "  $TOPOLOGY_FILE"
    exit 1
fi

# ============================================================
# Header
# ============================================================

echo
echo "=============================================="
echo " Fabric Peer Channel Join"
echo "=============================================="
echo

echo "Topology:"
echo "  $TOPOLOGY_FILE"
echo

echo "Assignments:"

for assignment in "${ASSIGNMENTS[@]}"; do
    PEER_NAME="${assignment%%:*}"
    CHANNEL_NAME="${assignment#*:}"

    echo "  ${PEER_NAME} -> ${CHANNEL_NAME}"
done

echo

# ============================================================
# Join peers
# ============================================================

for assignment in "${ASSIGNMENTS[@]}"; do

    PEER_NAME="${assignment%%:*}"
    CHANNEL_NAME="${assignment#*:}"

    CHANNEL_BLOCK="$CHANNEL_DIR/${CHANNEL_NAME}/channel.block"

    echo
    echo "----------------------------------------------"
    echo " Peer:    ${PEER_NAME}"
    echo " Channel: ${CHANNEL_NAME}"
    echo " Block:   ${CHANNEL_BLOCK}"
    echo "----------------------------------------------"

    # --------------------------------------------------------
    # Validate channel block
    # --------------------------------------------------------

    if [ ! -f "$CHANNEL_BLOCK" ]; then
        echo "ERROR: Channel block does not exist:"
        echo "  $CHANNEL_BLOCK"
        exit 1
    fi

    # --------------------------------------------------------
    # Validate peer
    # --------------------------------------------------------

    if ! docker inspect "$PEER_NAME" >/dev/null 2>&1; then
        echo "ERROR: Peer container does not exist:"
        echo "  $PEER_NAME"
        exit 1
    fi

    PEER_STATUS="$(docker inspect -f '{{.State.Status}}' "$PEER_NAME")"

    if [ "$PEER_STATUS" != "running" ]; then
        echo "ERROR: Peer container is not running:"
        echo "  $PEER_NAME"
        exit 1
    fi

    # --------------------------------------------------------
    # Copy channel block into peer container
    # --------------------------------------------------------

    echo "Copying channel block..."

    docker cp \
        "$CHANNEL_BLOCK" \
        "${PEER_NAME}:/tmp/${CHANNEL_NAME}.block"

    # --------------------------------------------------------
    # Join channel
    # --------------------------------------------------------

    echo "Joining ${CHANNEL_NAME}..."

    docker exec \
        -e CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/admin-msp \
        "$PEER_NAME" \
        peer channel join \
        -b "/tmp/${CHANNEL_NAME}.block"

    echo
    echo "SUCCESS:"
    echo "  ${PEER_NAME} -> ${CHANNEL_NAME}"

done

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " Peer Channel Join Complete"
echo "=============================================="
echo

echo "All topology assignments have been processed."
echo