#!/bin/bash

set -euo pipefail

# ============================================================
# Fabric Orderer Channel Bootstrap
#
# Joins the single Fabric orderer to every generated
# application channel using the Channel Participation API.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

BUILD_DIR="$PROJECT_ROOT/build/fabric-network"
CHANNEL_DIR="$BUILD_DIR/channels"
TOPOLOGY_FILE="$BUILD_DIR/topology.json"

ORDERER_CONTAINER="fabric-orderer-1"

FABRIC_TOOLS_IMAGE="${FABRIC_TOOLS_IMAGE:-hyperledger/fabric-tools:2.5.16}"

CONTAINER_PROJECT_ROOT="/fabric-project"

# ============================================================
# Orderer Admin API
#
# The orderer's TLS certificate is issued for 10.10.0.20.
# Therefore osnadmin must connect using that address so TLS
# hostname verification succeeds.
#
# IMPORTANT:
# osnadmin expects HOST:PORT here, NOT https://HOST:PORT.
# ============================================================

ORDERER_ADMIN_ADDRESS="${ORDERER_ADMIN_ADDRESS:-10.10.0.20:9443}"

# ============================================================
# Orderer TLS material
# ============================================================

ORDERER_TLS_DIR="$PROJECT_ROOT/build/fabric-bootstrap/orderer/tls"

ORDERER_TLS_CA="$ORDERER_TLS_DIR/ca.crt"
ORDERER_TLS_CERT="$ORDERER_TLS_DIR/server.crt"
ORDERER_TLS_KEY="$ORDERER_TLS_DIR/server.key"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TOPOLOGY_FILE" ]; then
    echo
    echo "Error: topology manifest does not exist:"
    echo "  $TOPOLOGY_FILE"
    echo
    echo "Run:"
    echo "  ./scripts/fabric-network/create.sh <peers> <ledgers> [seed]"
    echo
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$ORDERER_CONTAINER"; then
    echo
    echo "Error: ${ORDERER_CONTAINER} is not running."
    echo
    exit 1
fi

for FILE in \
    "$ORDERER_TLS_CA" \
    "$ORDERER_TLS_CERT" \
    "$ORDERER_TLS_KEY"
do
    if [ ! -f "$FILE" ]; then
        echo
        echo "Error: required orderer TLS file does not exist:"
        echo "  $FILE"
        echo
        exit 1
    fi
done

if [ ! -d "$CHANNEL_DIR" ]; then
    echo
    echo "Error: channel directory does not exist:"
    echo "  $CHANNEL_DIR"
    echo
    exit 1
fi

# ============================================================
# Read topology
# ============================================================

LEDGER_COUNT="$(
    python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["experiment"]["ledger_count"])
PY
)"

ORDERER_NAME="$(
    python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["fabric"]["orderer"])
PY
)"

ORDERER_COUNT="$(
    python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

print(topology["fabric"]["orderer_count"])
PY
)"

# ============================================================
# Validate single-orderer architecture
# ============================================================

if [ "$ORDERER_COUNT" -ne 1 ]; then
    echo
    echo "Error: this experiment requires exactly one orderer."
    echo
    echo "Configured orderer count: $ORDERER_COUNT"
    echo
    exit 1
fi

if [ "$ORDERER_NAME" != "$ORDERER_CONTAINER" ]; then
    echo
    echo "Error: topology orderer does not match running orderer."
    echo
    echo "Topology: $ORDERER_NAME"
    echo "Running:  $ORDERER_CONTAINER"
    echo
    exit 1
fi

if ! [[ "$LEDGER_COUNT" =~ ^[0-9]+$ ]] || [ "$LEDGER_COUNT" -lt 1 ]; then
    echo
    echo "Error: invalid ledger count: $LEDGER_COUNT"
    echo
    exit 1
fi

# ============================================================
# Fabric tools image
# ============================================================

if ! docker image inspect "$FABRIC_TOOLS_IMAGE" >/dev/null 2>&1; then

    echo
    echo "Fabric tooling:"
    echo "  $FABRIC_TOOLS_IMAGE"
    echo
    echo "Fabric tools image is not present locally."
    echo
    echo "Pulling:"
    echo "  $FABRIC_TOOLS_IMAGE"
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
echo "  $ORDERER_CONTAINER"
echo
echo "Orderer Admin API:"
echo "  $ORDERER_ADMIN_ADDRESS"
echo
echo "Channels:"
echo "  $LEDGER_COUNT"
echo
echo "TLS:"
echo "  CA:          $ORDERER_TLS_CA"
echo "  Client cert: $ORDERER_TLS_CERT"
echo "  Client key:  $ORDERER_TLS_KEY"
echo

# ============================================================
# Check Admin API
# ============================================================

echo "Checking orderer Admin API..."

docker run --rm \
    --network "container:${ORDERER_CONTAINER}" \
    -v "$ORDERER_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
    -v "$ORDERER_TLS_CERT:${CONTAINER_PROJECT_ROOT}/orderer-client.crt:ro" \
    -v "$ORDERER_TLS_KEY:${CONTAINER_PROJECT_ROOT}/orderer-client.key:ro" \
    "$FABRIC_TOOLS_IMAGE" \
    osnadmin \
    channel \
    list \
    -o "$ORDERER_ADMIN_ADDRESS" \
    --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt" \
    --client-cert "${CONTAINER_PROJECT_ROOT}/orderer-client.crt" \
    --client-key "${CONTAINER_PROJECT_ROOT}/orderer-client.key"

echo
echo "Orderer Admin API is reachable."
echo

# ============================================================
# Join every generated channel
# ============================================================

for CHANNEL_NUMBER in $(seq 1 "$LEDGER_COUNT"); do

    CHANNEL_NAME="channel-${CHANNEL_NUMBER}"
    CHANNEL_BLOCK="$CHANNEL_DIR/$CHANNEL_NAME/channel.block"

    if [ ! -s "$CHANNEL_BLOCK" ]; then
        echo
        echo "Error: channel block does not exist:"
        echo "  $CHANNEL_BLOCK"
        echo
        exit 1
    fi

    echo "=============================================="
    echo " Joining ${CHANNEL_NAME}"
    echo "=============================================="
    echo
    echo "Block:"
    echo "  $CHANNEL_BLOCK"
    echo

    docker run --rm \
        --network "container:${ORDERER_CONTAINER}" \
        -v "$CHANNEL_BLOCK:${CONTAINER_PROJECT_ROOT}/channel.block:ro" \
        -v "$ORDERER_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
        -v "$ORDERER_TLS_CERT:${CONTAINER_PROJECT_ROOT}/orderer-client.crt:ro" \
        -v "$ORDERER_TLS_KEY:${CONTAINER_PROJECT_ROOT}/orderer-client.key:ro" \
        "$FABRIC_TOOLS_IMAGE" \
        osnadmin \
        channel \
        join \
        -o "$ORDERER_ADMIN_ADDRESS" \
        --channelID "$CHANNEL_NAME" \
        --config-block "${CONTAINER_PROJECT_ROOT}/channel.block" \
        --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt" \
        --client-cert "${CONTAINER_PROJECT_ROOT}/orderer-client.crt" \
        --client-key "${CONTAINER_PROJECT_ROOT}/orderer-client.key"

    echo
    echo "  ${CHANNEL_NAME}: joined"
    echo

done

# ============================================================
# Verify final channel membership
# ============================================================

echo
echo "=============================================="
echo " Verifying orderer channel membership"
echo "=============================================="
echo

docker run --rm \
    --network "container:${ORDERER_CONTAINER}" \
    -v "$ORDERER_TLS_CA:${CONTAINER_PROJECT_ROOT}/orderer-ca.crt:ro" \
    -v "$ORDERER_TLS_CERT:${CONTAINER_PROJECT_ROOT}/orderer-client.crt:ro" \
    -v "$ORDERER_TLS_KEY:${CONTAINER_PROJECT_ROOT}/orderer-client.key:ro" \
    "$FABRIC_TOOLS_IMAGE" \
    osnadmin \
    channel \
    list \
    -o "$ORDERER_ADMIN_ADDRESS" \
    --ca-file "${CONTAINER_PROJECT_ROOT}/orderer-ca.crt" \
    --client-cert "${CONTAINER_PROJECT_ROOT}/orderer-client.crt" \
    --client-key "${CONTAINER_PROJECT_ROOT}/orderer-client.key"

echo
echo "=============================================="
echo " Orderer channel bootstrap complete"
echo "=============================================="
echo
echo "Orderer:"
echo "  $ORDERER_CONTAINER"
echo
echo "Channels:"
echo "  $LEDGER_COUNT"
echo
echo "The single orderer is participating in all"
echo "generated application channels."
echo