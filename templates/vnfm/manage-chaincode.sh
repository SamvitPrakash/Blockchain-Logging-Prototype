#!/bin/bash

set -euo pipefail

: "${VNFM_MSP_ID:?VNFM_MSP_ID is required}"
: "${VNFM_MSPCONFIGPATH:?VNFM_MSPCONFIGPATH is required}"
: "${VNFM_TOPOLOGY_FILE:?VNFM_TOPOLOGY_FILE is required}"
: "${VNFM_ORDERER_ENDPOINT:?VNFM_ORDERER_ENDPOINT is required}"
: "${VNFM_TLS_CA:?VNFM_TLS_CA is required}"
: "${VNFM_CHAINCODE_PATH:?VNFM_CHAINCODE_PATH is required}"

CHAINCODE_NAME="${VNFM_CHAINCODE_NAME:-logging}"
CHAINCODE_VERSION="${VNFM_CHAINCODE_VERSION:-1.0}"
CHAINCODE_SEQUENCE="${VNFM_CHAINCODE_SEQUENCE:-1}"

PACKAGE_DIR="/tmp/vnfm-chaincode"
PACKAGE_FILE="${PACKAGE_DIR}/${CHAINCODE_NAME}.tar.gz"
PACKAGE_LABEL="${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

export CORE_PEER_LOCALMSPID="$VNFM_MSP_ID"
export CORE_PEER_MSPCONFIGPATH="$VNFM_MSPCONFIGPATH"
export CORE_PEER_TLS_ENABLED=true

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

test -f "$VNFM_TOPOLOGY_FILE"
test -d "$VNFM_MSPCONFIGPATH"
test -f "$VNFM_MSPCONFIGPATH/signcerts/cert.pem"
test -f "$VNFM_MSPCONFIGPATH/config.yaml"
test -f "$VNFM_TLS_CA"
test -d "$VNFM_CHAINCODE_PATH"

# ------------------------------------------------------------
# Topology helpers
# ------------------------------------------------------------

get_channels()
{
    python3 - "$VNFM_TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

for channel in topology["channels"]:
    print(channel)
PY
}

get_peers()
{
    local channel="$1"

    python3 - "$VNFM_TOPOLOGY_FILE" "$channel" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

channel = sys.argv[2]

for peer in topology["channels"][channel]:
    print(peer)
PY
}

# ------------------------------------------------------------
# Peer configuration
# ------------------------------------------------------------

configure_peer()
{
    local peer="$1"

    export CORE_PEER_ADDRESS="${peer}:7051"
    export CORE_PEER_TLS_ROOTCERT_FILE="$VNFM_TLS_CA"

    echo
    echo "Peer:"
    echo "  ${CORE_PEER_ADDRESS}"
    echo "TLS CA:"
    echo "  ${CORE_PEER_TLS_ROOTCERT_FILE}"
}

# ------------------------------------------------------------
# Package
# ------------------------------------------------------------

package_chaincode()
{
    echo
    echo "Packaging ${CHAINCODE_NAME}..."

    rm -rf "$PACKAGE_DIR"
    mkdir -p "$PACKAGE_DIR"

    peer lifecycle chaincode package \
        "$PACKAGE_FILE" \
        --path "$VNFM_CHAINCODE_PATH" \
        --lang node \
        --label "$PACKAGE_LABEL"

    if [ ! -s "$PACKAGE_FILE" ]; then
        echo "ERROR: chaincode package was not generated."
        exit 1
    fi
}

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

install_chaincode()
{
    local peer="$1"

    echo
    echo "Installing ${CHAINCODE_NAME} on ${peer}..."

    configure_peer "$peer"

    peer lifecycle chaincode install \
        "$PACKAGE_FILE"
}

# ------------------------------------------------------------
# Package ID
# ------------------------------------------------------------

get_package_id()
{
    local peer="$1"

    configure_peer "$peer"

    peer lifecycle chaincode queryinstalled |
        sed -n 's/.*Package ID: \([^,]*\), Label: '"$PACKAGE_LABEL"'.*/\1/p' |
        head -n 1
}

# ------------------------------------------------------------
# Approve
# ------------------------------------------------------------

approve_chaincode()
{
    local peer="$1"
    local channel="$2"
    local package_id="$3"

    echo
    echo "Approving ${CHAINCODE_NAME}"
    echo "  Channel : ${channel}"
    echo "  Peer    : ${peer}"

    configure_peer "$peer"

    peer lifecycle chaincode approveformyorg \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME" \
        --version "$CHAINCODE_VERSION" \
        --sequence "$CHAINCODE_SEQUENCE" \
        --package-id "$package_id" \
        --orderer "$VNFM_ORDERER_ENDPOINT" \
        --tls \
        --cafile "$VNFM_TLS_CA"
}

# ------------------------------------------------------------
# Commit
# ------------------------------------------------------------

commit_chaincode()
{
    local channel="$1"
    shift

    local peers=( "$@" )
    local args=()

    for peer in "${peers[@]}"; do
        args+=(
            --peerAddresses "${peer}:7051"
            --tlsRootCertFiles "$VNFM_TLS_CA"
        )
    done

    echo
    echo "Committing ${CHAINCODE_NAME}"
    echo "  Channel : ${channel}"

    configure_peer "${peers[0]}"

    peer lifecycle chaincode commit \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME" \
        --version "$CHAINCODE_VERSION" \
        --sequence "$CHAINCODE_SEQUENCE" \
        --orderer "$VNFM_ORDERER_ENDPOINT" \
        --tls \
        --cafile "$VNFM_TLS_CA" \
        "${args[@]}"
}

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

verify_chaincode()
{
    local channel="$1"
    local peer="$2"

    configure_peer "$peer"

    peer lifecycle chaincode querycommitted \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

echo
echo "=============================================="
echo " VNFM Chaincode Lifecycle"
echo "=============================================="
echo

package_chaincode

mapfile -t CHANNELS < <(get_channels)

if [ "${#CHANNELS[@]}" -eq 0 ]; then
    echo "ERROR: topology contains no channels."
    exit 1
fi

for channel in "${CHANNELS[@]}"; do

    mapfile -t PEERS < <(get_peers "$channel")

    if [ "${#PEERS[@]}" -eq 0 ]; then
        echo "ERROR: ${channel} contains no peers."
        exit 1
    fi

    echo
    echo "=============================================="
    echo " ${channel}"
    echo "=============================================="

    # Install on every peer assigned to this channel.
    for peer in "${PEERS[@]}"; do
        install_chaincode "$peer"
    done

    # Determine package ID from the first participating peer.
    PACKAGE_ID=""

    for peer in "${PEERS[@]}"; do
        PACKAGE_ID="$(get_package_id "$peer" || true)"

        if [ -n "$PACKAGE_ID" ]; then
            break
        fi
    done

    if [ -z "$PACKAGE_ID" ]; then
        echo "ERROR: package ID could not be determined."
        exit 1
    fi

    echo
    echo "Package ID:"
    echo "  ${PACKAGE_ID}"

    approve_chaincode \
        "${PEERS[0]}" \
        "$channel" \
        "$PACKAGE_ID"

    commit_chaincode \
        "$channel" \
        "${PEERS[@]}"

    verify_chaincode \
        "$channel" \
        "${PEERS[0]}"

done

echo
echo "=============================================="
echo " Chaincode deployment complete"
echo "=============================================="
echo