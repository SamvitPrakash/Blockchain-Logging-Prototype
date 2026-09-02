#!/bin/bash

set -e

# ============================================================
# VNFM - Orderer Channel Bootstrap
# ============================================================

TOPOLOGY_FILE="${VNFM_TOPOLOGY_FILE:-/opt/vnfm-state/topology.json}"
CHANNEL_BLOCK_DIR="${VNFM_CHANNEL_BLOCK_DIR:-/opt/vnfm-state/channels}"

ORDERER_NAME="${VNFM_ORDERER_NAME:-fabric-orderer-1}"
ORDERER_ADMIN_ENDPOINT="${VNFM_ORDERER_ADMIN_ENDPOINT:-fabric-orderer-1:9443}"

TLS_CA="${VNFM_TLS_CA}"
TLS_CLIENT_CERT="${VNFM_TLS_CLIENT_CERT}"
TLS_CLIENT_KEY="${VNFM_TLS_CLIENT_KEY}"

WAIT_INTERVAL="${VNFM_WAIT_INTERVAL:-2}"
WAIT_TIMEOUT="${VNFM_WAIT_TIMEOUT:-120}"

# ============================================================
# Helpers
# ============================================================

fail()
{
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

require_file()
{
    local file="$1"

    if [ ! -f "$file" ]; then
        fail "Required file does not exist: $file"
    fi
}

# ============================================================
# Validate VNFM state
# ============================================================

require_file "$TOPOLOGY_FILE"
require_file "$TLS_CA"
require_file "$TLS_CLIENT_CERT"
require_file "$TLS_CLIENT_KEY"

if [ ! -d "$CHANNEL_BLOCK_DIR" ]; then
    fail "Channel block directory does not exist: $CHANNEL_BLOCK_DIR"
fi

# ============================================================
# Discover generated channels
#
# The Fabric network generator creates one directory per
# channel containing channel.block.
#
# We deliberately discover these files rather than requiring
# a JSON parser inside the VNFM container.
# ============================================================

mapfile -t CHANNEL_BLOCKS < <(
    find "$CHANNEL_BLOCK_DIR" \
        -mindepth 2 \
        -maxdepth 2 \
        -type f \
        -name "channel.block" \
        | sort
)

if [ "${#CHANNEL_BLOCKS[@]}" -eq 0 ]; then
    fail "No channel blocks were found in ${CHANNEL_BLOCK_DIR}."
fi

# ============================================================
# Display configuration
# ============================================================

echo
echo "=============================================="
echo " Fabric Orderer Channel Bootstrap"
echo "=============================================="
echo

echo "Orderer:"
echo "  ${ORDERER_NAME}"

echo
echo "Orderer Admin API:"
echo "  https://${ORDERER_ADMIN_ENDPOINT}"

echo
echo "Channels:"
echo "  ${#CHANNEL_BLOCKS[@]}"

echo
echo "TLS:"
echo "  CA:           ${TLS_CA}"
echo "  Client cert:  ${TLS_CLIENT_CERT}"
echo "  Client key:   ${TLS_CLIENT_KEY}"

# ============================================================
# Wait for Orderer Admin API
# ============================================================

echo
echo "Checking orderer Admin API..."

START_TIME="$(date +%s)"

while true; do

    if osnadmin channel list \
        -o "$ORDERER_ADMIN_ENDPOINT" \
        --ca-file "$TLS_CA" \
        --client-cert "$TLS_CLIENT_CERT" \
        --client-key "$TLS_CLIENT_KEY" \
        >/tmp/vnfm-channel-list.json \
        2>/tmp/vnfm-channel-list.err
    then
        echo
        echo "Orderer Admin API is reachable."
        break
    fi

    NOW="$(date +%s)"
    ELAPSED="$((NOW - START_TIME))"

    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo
        echo "Orderer Admin API did not become available."
        echo
        cat /tmp/vnfm-channel-list.err || true
        exit 1
    fi

    echo "  Waiting for orderer Admin API..."
    sleep "$WAIT_INTERVAL"
done

# ============================================================
# Join channels
# ============================================================

for BLOCK in "${CHANNEL_BLOCKS[@]}"; do

    CHANNEL_DIR="$(dirname "$BLOCK")"
    CHANNEL="$(basename "$CHANNEL_DIR")"

    echo
    echo "=============================================="
    echo " Joining ${CHANNEL}"
    echo "=============================================="
    echo

    echo "Block:"
    echo "  ${BLOCK}"

    require_file "$BLOCK"

    # --------------------------------------------------------
    # Check whether the orderer already participates.
    # --------------------------------------------------------

    if osnadmin channel list \
        -o "$ORDERER_ADMIN_ENDPOINT" \
        --ca-file "$TLS_CA" \
        --client-cert "$TLS_CLIENT_CERT" \
        --client-key "$TLS_CLIENT_KEY" \
        | grep -q "\"name\": \"${CHANNEL}\""
    then
        echo
        echo "  ${CHANNEL}: already joined"
        continue
    fi

    # --------------------------------------------------------
    # Join the channel.
    # --------------------------------------------------------

    osnadmin channel join \
        --channelID="$CHANNEL" \
        --config-block="$BLOCK" \
        -o "$ORDERER_ADMIN_ENDPOINT" \
        --ca-file "$TLS_CA" \
        --client-cert="$TLS_CLIENT_CERT" \
        --client-key="$TLS_CLIENT_KEY"

    echo
    echo "  ${CHANNEL}: joined"

done

# ============================================================
# Verify membership
# ============================================================

echo
echo "=============================================="
echo " Verifying orderer channel membership"
echo "=============================================="
echo

osnadmin channel list \
    -o "$ORDERER_ADMIN_ENDPOINT" \
    --ca-file "$TLS_CA" \
    --client-cert "$TLS_CLIENT_CERT" \
    --client-key "$TLS_CLIENT_KEY"

echo
echo "=============================================="
echo " Orderer channel bootstrap complete"
echo "=============================================="
echo

echo "Orderer:"
echo "  ${ORDERER_NAME}"

echo
echo "Channels:"
echo "  ${#CHANNEL_BLOCKS[@]}"

echo
echo "VNFM is ready."
echo

# ============================================================
# Keep VNFM alive.
#
# Future management services will replace this idle process.
# ============================================================

# exec tail -f /dev/null