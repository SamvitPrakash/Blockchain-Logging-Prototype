#!/bin/bash

set -euo pipefail

: "${VNFM_MSP_ID:?VNFM_MSP_ID is required}"
: "${VNFM_MSPCONFIGPATH:?VNFM_MSPCONFIGPATH is required}"
: "${VNFM_TOPOLOGY_FILE:?VNFM_TOPOLOGY_FILE is required}"
: "${VNFM_ORDERER_ENDPOINT:?VNFM_ORDERER_ENDPOINT is required}"
: "${VNFM_TLS_CA:?VNFM_TLS_CA is required}"
: "${VNFM_CHAINCODE_PATH:?VNFM_CHAINCODE_PATH is required}"
: "${VNFM_CHANNEL_BLOCK_DIR:?VNFM_CHANNEL_BLOCK_DIR is required}"

CHAINCODE_NAME="${VNFM_CHAINCODE_NAME:-logging}"
CHAINCODE_VERSION="${VNFM_CHAINCODE_VERSION:-1.0}"
CHAINCODE_SEQUENCE="${VNFM_CHAINCODE_SEQUENCE:-1}"

WAIT_INTERVAL="${VNFM_WAIT_INTERVAL:-2}"
WAIT_TIMEOUT="${VNFM_WAIT_TIMEOUT:-120}"

PACKAGE_DIR="/tmp/vnfm-chaincode"
PACKAGE_FILE="${PACKAGE_DIR}/${CHAINCODE_NAME}.tar.gz"
PACKAGE_LABEL="${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

export CORE_PEER_LOCALMSPID="${VNFM_MSP_ID}"
export CORE_PEER_MSPCONFIGPATH="${VNFM_MSPCONFIGPATH}"
export CORE_PEER_TLS_ENABLED=true

# ============================================================
# Helpers
# ============================================================

get_channels()
{
    python3 - "${VNFM_TOPOLOGY_FILE}" <<'PY'
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

    python3 - "${VNFM_TOPOLOGY_FILE}" "${channel}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

channel = sys.argv[2]

for peer in topology["channels"][channel]:
    print(peer)
PY
}

configure_peer()
{
    local peer="$1"

    export CORE_PEER_ADDRESS="${peer}:7051"
    export CORE_PEER_TLS_ROOTCERT_FILE="${VNFM_TLS_CA}"

    echo
    echo "Peer:"
    echo "  ${CORE_PEER_ADDRESS}"
    echo "TLS CA:"
    echo "  ${CORE_PEER_TLS_ROOTCERT_FILE}"
}

wait_for_peer()
{
    local peer="$1"

    echo
    echo "Waiting for ${peer}:7051..."

    local elapsed=0

    while true; do
        configure_peer "${peer}"

        if peer node status >/dev/null 2>&1; then
            echo "  ${peer}: peer is ready."
            return 0
        fi

        if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
            echo "ERROR: timed out waiting for ${peer}:7051"
            return 1
        fi

        sleep "${WAIT_INTERVAL}"
        elapsed=$((elapsed + WAIT_INTERVAL))
    done
}

channel_block()
{
    local channel="$1"
    echo "${VNFM_CHANNEL_BLOCK_DIR}/${channel}/channel.block"
}

join_channel()
{
    local peer="$1"
    local channel="$2"

    configure_peer "${peer}"

    echo
    echo "Checking ${peer} membership in ${channel}..."

    if peer channel list 2>/dev/null |
        grep -qE "(^|[[:space:]])${channel}([[:space:]]|$)"; then

        echo "  ${peer}: already joined ${channel}"
        return 0
    fi

    local block
    block="$(channel_block "${channel}")"

    if [ ! -s "${block}" ]; then
        echo "ERROR: channel block does not exist:"
        echo "  ${block}"
        return 1
    fi

    echo
    echo "Joining ${peer} to ${channel}"
    echo "Block:"
    echo "  ${block}"

    peer channel join \
        -b "${block}"

    echo "  ${peer}: joined ${channel}"
}

package_chaincode()
{
    echo
    echo "Packaging ${CHAINCODE_NAME}..."

    rm -rf "${PACKAGE_DIR}"
    mkdir -p "${PACKAGE_DIR}"

    peer lifecycle chaincode package \
        "${PACKAGE_FILE}" \
        --path "${VNFM_CHAINCODE_PATH}" \
        --lang node \
        --label "${PACKAGE_LABEL}"

    test -s "${PACKAGE_FILE}" || {
        echo "ERROR: chaincode package was not generated."
        exit 1
    }

    echo
    echo "Package:"
    echo "  ${PACKAGE_FILE}"
}

install_chaincode()
{
    local peer="$1"

    configure_peer "${peer}"

    echo
    echo "Installing ${CHAINCODE_NAME} on ${peer}..."

    peer lifecycle chaincode install \
        "${PACKAGE_FILE}"

    echo "  ${peer}: installation complete."
}

get_package_id()
{
    local peer="$1"

    configure_peer "${peer}"

    peer lifecycle chaincode queryinstalled 2>/dev/null |
        sed -n \
        's/.*Package ID: \([^,]*\), Label: '"${PACKAGE_LABEL}"'.*/\1/p' |
        head -n 1
}

approve_chaincode()
{
    local peer="$1"
    local channel="$2"
    local package_id="$3"

    configure_peer "${peer}"

    echo
    echo "Approving ${CHAINCODE_NAME}"
    echo "  Channel : ${channel}"
    echo "  Peer    : ${peer}"

    peer lifecycle chaincode approveformyorg \
        --channelID "${channel}" \
        --name "${CHAINCODE_NAME}" \
        --version "${CHAINCODE_VERSION}" \
        --sequence "${CHAINCODE_SEQUENCE}" \
        --package-id "${package_id}" \
        --orderer "${VNFM_ORDERER_ENDPOINT}" \
        --tls \
        --cafile "${VNFM_TLS_CA}"

    echo "  ${peer}: approval submitted."
}

commit_chaincode()
{
    local channel="$1"
    shift

    local peers=( "$@" )
    local args=()

    for peer in "${peers[@]}"; do
        args+=(
            --peerAddresses "${peer}:7051"
            --tlsRootCertFiles "${VNFM_TLS_CA}"
        )
    done

    configure_peer "${peers[0]}"

    echo
    echo "Committing ${CHAINCODE_NAME}"
    echo "  Channel : ${channel}"
    echo "  Peers   : ${peers[*]}"

    peer lifecycle chaincode commit \
        --channelID "${channel}" \
        --name "${CHAINCODE_NAME}" \
        --version "${CHAINCODE_VERSION}" \
        --sequence "${CHAINCODE_SEQUENCE}" \
        --orderer "${VNFM_ORDERER_ENDPOINT}" \
        --tls \
        --cafile "${VNFM_TLS_CA}" \
        "${args[@]}"

    echo "  ${channel}: chaincode committed."
}

verify_chaincode()
{
    local channel="$1"
    local peer="$2"

    configure_peer "${peer}"

    echo
    echo "Verifying ${CHAINCODE_NAME} on ${channel}..."

    peer lifecycle chaincode querycommitted \
        --channelID "${channel}" \
        --name "${CHAINCODE_NAME}"
}

# ============================================================
# Main
# ============================================================

echo
echo "=============================================="
echo " VNFM Chaincode Lifecycle"
echo "=============================================="
echo

test -f "${VNFM_TOPOLOGY_FILE}"
test -d "${VNFM_MSPCONFIGPATH}"
test -f "${VNFM_MSPCONFIGPATH}/signcerts/cert.pem"
test -f "${VNFM_MSPCONFIGPATH}/config.yaml"
test -f "${VNFM_TLS_CA}"
test -d "${VNFM_CHAINCODE_PATH}"

mapfile -t CHANNELS < <(get_channels)

if [ "${#CHANNELS[@]}" -eq 0 ]; then
    echo "ERROR: topology contains no channels."
    exit 1
fi

package_chaincode

for channel in "${CHANNELS[@]}"; do

    mapfile -t PEERS < <(get_peers "${channel}")

    if [ "${#PEERS[@]}" -eq 0 ]; then
        echo "ERROR: ${channel} contains no peers."
        exit 1
    fi

    echo
    echo "=============================================="
    echo " ${channel}"
    echo "=============================================="

    # --------------------------------------------------------
    # Peers must be alive and joined before chaincode
    # installation.
    # --------------------------------------------------------

    for peer in "${PEERS[@]}"; do
        wait_for_peer "${peer}"
        join_channel "${peer}" "${channel}"
    done

    # --------------------------------------------------------
    # Install chaincode on every channel peer.
    # --------------------------------------------------------

    for peer in "${PEERS[@]}"; do
        install_chaincode "${peer}"
    done

    # --------------------------------------------------------
    # Determine package ID.
    # --------------------------------------------------------

    PACKAGE_ID=""

    for peer in "${PEERS[@]}"; do
        PACKAGE_ID="$(get_package_id "${peer}" || true)"

        if [ -n "${PACKAGE_ID}" ]; then
            break
        fi
    done

    if [ -z "${PACKAGE_ID}" ]; then
        echo "ERROR: package ID could not be determined."
        exit 1
    fi

    echo
    echo "Package ID:"
    echo "  ${PACKAGE_ID}"

    # --------------------------------------------------------
    # Approve.
    # --------------------------------------------------------

    approve_chaincode \
        "${PEERS[0]}" \
        "${channel}" \
        "${PACKAGE_ID}"

    # --------------------------------------------------------
    # Commit.
    # --------------------------------------------------------

    commit_chaincode \
        "${channel}" \
        "${PEERS[@]}"

    # --------------------------------------------------------
    # Verify.
    # --------------------------------------------------------

    verify_chaincode \
        "${channel}" \
        "${PEERS[0]}"

done

echo
echo "=============================================="
echo " Chaincode deployment complete"
echo "=============================================="
echo