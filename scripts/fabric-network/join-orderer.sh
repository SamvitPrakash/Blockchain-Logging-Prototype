#!/bin/bash

set -euo pipefail

# ============================================================
# FABRIC-NETWORK
#
# Joins the existing SINGLE Fabric orderer to every generated
# application channel.
#
# The orderer must already be running.
#
# Usage:
#   ./scripts/fabric-network/join-orderer.sh
#
# Expected generated structure:
#
#   build/fabric-network/
#   ├── topology.json
#   ├── configtx.yaml
#   └── channels/
#       ├── channel-1/channel.block
#       ├── channel-2/channel.block
#       └── ...
#
# Architecture:
#
#                   fabric-orderer-1
#                         │
#             ┌───────────┼───────────┐
#             ▼           ▼           ▼
#         channel-1   channel-2   channel-3
#
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

BUILD_DIR="$PROJECT_ROOT/build/fabric-network"
CHANNEL_DIR="$BUILD_DIR/channels"
TOPOLOGY_FILE="$BUILD_DIR/topology.json"

ORDERER_CONTAINER="fabric-orderer-1"

# Fabric tools image used for osnadmin.
FABRIC_TOOLS_IMAGE="${FABRIC_TOOLS_IMAGE:-hyperledger/fabric-tools:2.5.16}"

# Container-side mount point.
CONTAINER_PROJECT_ROOT="/fabric-project"

# Existing orderer admin endpoint.
#
# This assumes the orderer is configured with the standard
# Fabric orderer admin API.
ORDERER_ADMIN_ADDRESS="${ORDERER_ADMIN_ADDRESS:-fabric-orderer-1:7053}"

ORDERER_ADMIN_TLS_CERT="$PROJECT_ROOT/build/fabric-bootstrap/orderer/tls/server.crt"
ORDERER_ADMIN_TLS_KEY="$PROJECT_ROOT/build/fabric-bootstrap/orderer/tls/server.key"
ORDERER_ADMIN_TLS_CA="$PROJECT_ROOT/build/fabric-bootstrap/orderer/tls/ca.crt"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TOPOLOGY_FILE" ]; then
    echo "Error: topology manifest does not exist:"
    echo "  $TOPOLOGY_FILE"
    echo
    echo "Run:"
    echo
    echo "  ./scripts/fabric-network/create.sh <peers> <ledgers> [seed]"
    echo
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$ORDERER_CONTAINER"; then
    echo "Error: ${ORDERER_CONTAINER} is not running."
    echo
    echo "Current containers:"
    docker ps --format '  {{.Names}}\t{{.Status}}'
    echo
    exit 1
fi

if [ ! -f "$ORDERER_ADMIN_TLS_CERT" ]; then
    echo "Error: orderer TLS certificate not found:"
    echo "  $ORDERER_ADMIN_TLS_CERT"
    exit 1
fi

if [ ! -f "$ORDERER_ADMIN_TLS_CA" ]; then
    echo "Error: orderer TLS CA certificate not found:"
    echo "  $ORDERER_ADMIN_TLS_CA"
    exit 1
fi

# ============================================================
# Read topology
# ============================================================

LEDGER_COUNT="$(python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["experiment"]["ledger_count"])
PY
)"

ORDERER_NAME="$(python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["fabric"]["orderer"])
PY
)"

ORDERER_COUNT="$(python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["fabric"]["orderer_count"])
PY
)"

# ============================================================
# Enforce single-orderer architecture
# ============================================================

if [ "$ORDERER_COUNT" -ne 1 ]; then
    echo "Error: topology does not describe a single-orderer deployment."
    echo
    echo "Configured orderer count: ${ORDERER_COUNT}"
    exit 1
fi

if [ "$ORDERER_NAME" != "$ORDERER_CONTAINER" ]; then
    echo "Error: topology orderer does not match running orderer."
    echo
    echo "Topology: ${ORDERER_NAME}"
    echo "Expected: ${ORDERER_CONTAINER}"
    exit 1
fi

# ============================================================
# Fabric tools image
# ============================================================

if ! docker image inspect "$FABRIC_TOOLS_IMAGE" >/dev/null 2>&1; then
    echo "Fabric tools image is not present locally."
    echo
    echo "Pulling:"
    echo "  ${FABRIC_TOOLS_IMAGE}"
    echo

    docker pull "$FABRIC_TOOLS_IMAGE"
fi

# ============================================================
# Display deployment
# ============================================================

echo
echo "=============================================="
echo " Fabric Orderer Channel Bootstrap"
echo "=============================================="
echo
echo "Orderer:"
echo "  ${ORDERER_CONTAINER}"
echo
echo "Orderer admin endpoint:"
echo "  ${ORDERER_ADMIN_ADDRESS}"
echo
echo "Channels:"
echo "  ${LEDGER_COUNT}"
echo

# ============================================================
# Verify orderer admin API
# ============================================================

echo "Checking orderer admin API..."

docker run --rm \
    --network container:"$ORDERER_CONTAINER" \
    -v "$ORDERER_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
    "$FABRIC_TOOLS_IMAGE" \
    osnadmin \
    channel \
    list \
    -o "https://${ORDERER_ADMIN_ADDRESS#*:}" \
    --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt"

echo
echo "Orderer admin API is reachable."
echo

# ============================================================
# Join every channel
# ============================================================

for CHANNEL_NUMBER in $(seq 1 "$LEDGER_COUNT"); do

    CHANNEL_NAME="channel-${CHANNEL_NUMBER}"

    CHANNEL_BLOCK="$CHANNEL_DIR/$CHANNEL_NAME/channel.block"

    if [ ! -s "$CHANNEL_BLOCK" ]; then
        echo "Error: channel block does not exist:"
        echo "  $CHANNEL_BLOCK"
        exit 1
    fi

    echo "Joining orderer to ${CHANNEL_NAME}..."

    docker run --rm \
        --network container:"$ORDERER_CONTAINER" \
        -v "$CHANNEL_BLOCK:${CONTAINER_PROJECT_ROOT}/channel.block:ro" \
        -v "$ORDERER_ADMIN_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
        "$FABRIC_TOOLS_IMAGE" \
        osnadmin \
        channel \
        join \
        -o "https://${ORDERER_ADMIN_ADDRESS#*:}" \
        --channelID "$CHANNEL_NAME" \
        --config-block "${CONTAINER_PROJECT_ROOT}/channel.block" \
        --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt"

    echo
    echo "  ${CHANNEL_NAME}: joined"
    echo
done

# ============================================================
# Verify channel membership
# ============================================================

echo "=============================================="
echo " Verifying orderer channel membership"
echo "=============================================="
echo

docker run --rm \
    --network container:"$ORDERER_CONTAINER" \
    -v "$ORDERER_ADMIN_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
    "$FABRIC_TOOLS_IMAGE" \
    osnadmin \
    channel \
    list \
    -o "https://${ORDERER_ADMIN_ADDRESS#*:}" \
    --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt"

echo
echo "=============================================="
echo " Orderer channel bootstrap complete"
echo "=============================================="