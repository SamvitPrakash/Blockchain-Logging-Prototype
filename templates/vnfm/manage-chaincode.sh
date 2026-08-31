#!/bin/bash

set -euo pipefail

# ============================================================
# VNFM Chaincode Lifecycle Manager
# ============================================================

TOPOLOGY_FILE="${VNFM_TOPOLOGY_FILE:?VNFM_TOPOLOGY_FILE is required}"

CHAINCODE_NAME="${VNFM_CHAINCODE_NAME:-logging}"
CHAINCODE_VERSION="${VNFM_CHAINCODE_VERSION:-1.0}"
CHAINCODE_SEQUENCE="${VNFM_CHAINCODE_SEQUENCE:-1}"

CHAINCODE_PATH="${VNFM_CHAINCODE_PATH:?VNFM_CHAINCODE_PATH is required}"

MSP_ID="${VNFM_MSP_ID:?VNFM_MSP_ID is required}"
MSP_CONFIG_PATH="${VNFM_MSPCONFIGPATH:?VNFM_MSPCONFIGPATH is required}"

ORDERER_ENDPOINT="${VNFM_ORDERER_ENDPOINT:?VNFM_ORDERER_ENDPOINT is required}"
ORDERER_TLS_CA="${VNFM_ORDERER_TLS_CA:?VNFM_ORDERER_TLS_CA is required}"

PEER_TLS_DIR="${VNFM_PEER_TLS_DIR:?VNFM_PEER_TLS_DIR is required}"

PACKAGE_DIR="/tmp/vnfm-chaincode"
PACKAGE_FILE="${PACKAGE_DIR}/${CHAINCODE_NAME}.tar.gz"
PACKAGE_LABEL="${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

# ============================================================
# Fabric CLI environment
# ============================================================

export CORE_PEER_LOCALMSPID="$MSP_ID"
export CORE_PEER_MSPCONFIGPATH="$MSP_CONFIG_PATH"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TOPOLOGY_FILE" ]; then
    echo "ERROR: topology file does not exist:"
    echo "  $TOPOLOGY_FILE"
    exit 1
fi

if [ ! -d "$CHAINCODE_PATH" ]; then
    echo "ERROR: chaincode directory does not exist:"
    echo "  $CHAINCODE_PATH"
    exit 1
fi

if [ ! -f "$CHAINCODE_PATH/package.json" ]; then
    echo "ERROR: chaincode package.json does not exist:"
    echo "  $CHAINCODE_PATH/package.json"
    exit 1
fi

if [ ! -f "$CHAINCODE_PATH/index.js" ]; then
    echo "ERROR: chaincode index.js does not exist:"
    echo "  $CHAINCODE_PATH/index.js"
    exit 1
fi

if [ ! -d "$MSP_CONFIG_PATH" ]; then
    echo "ERROR: VNFM MSP directory does not exist:"
    echo "  $MSP_CONFIG_PATH"
    exit 1
fi

if [ ! -f "$ORDERER_TLS_CA" ]; then
    echo "ERROR: orderer TLS CA does not exist:"
    echo "  $ORDERER_TLS_CA"
    exit 1
fi

if [ ! -d "$PEER_TLS_DIR" ]; then
    echo "ERROR: peer TLS directory does not exist:"
    echo "  $PEER_TLS_DIR"
    exit 1
fi

# ============================================================
# Topology helpers
# ============================================================

get_channels()
{
    python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

channels = topology.get("channels", {})

if not isinstance(channels, dict):
    raise SystemExit("ERROR: topology 'channels' is not an object")

for channel in sorted(channels):
    print(channel)
PY
}

get_peers_for_channel()
{
    local channel="$1"

    python3 - "$TOPOLOGY_FILE" "$channel" <<'PY'
import json
import sys

topology_file = sys.argv[1]
channel_name = sys.argv[2]

with open(topology_file, "r", encoding="utf-8") as f:
    topology = json.load(f)

channels = topology.get("channels", {})

if channel_name not in channels:
    raise SystemExit(
        f"ERROR: channel '{channel_name}' is not present in topology"
    )

peers = channels[channel_name]

if not isinstance(peers, list):
    raise SystemExit(
        f"ERROR: topology entry for '{channel_name}' is not a peer list"
    )

for peer in peers:
    if not isinstance(peer, str) or not peer:
        raise SystemExit(
            f"ERROR: invalid peer entry for '{channel_name}'"
        )

    print(peer)
PY
}

# ============================================================
# Peer helpers
# ============================================================

peer_tls_ca()
{
    local peer="$1"

    local ca_file="${PEER_TLS_DIR}/${peer}/ca.crt"

    if [ ! -f "$ca_file" ]; then
        echo "ERROR: TLS CA for peer '${peer}' does not exist:" >&2
        echo "  $ca_file" >&2
        return 1
    fi

    printf '%s\n' "$ca_file"
}

peer_address()
{
    local peer="$1"

    printf '%s:7051\n' "$peer"
}

set_peer_environment()
{
    local peer="$1"

    export CORE_PEER_ADDRESS
    export CORE_PEER_TLS_ENABLED
    export CORE_PEER_TLS_ROOTCERT_FILE

    CORE_PEER_ADDRESS="$(peer_address "$peer")"
    CORE_PEER_TLS_ENABLED="true"
    CORE_PEER_TLS_ROOTCERT_FILE="$(peer_tls_ca "$peer")"
}

# ============================================================
# Package
# ============================================================

package_chaincode()
{
    echo
    echo "=============================================="
    echo " Packaging chaincode"
    echo "=============================================="
    echo

    rm -rf "$PACKAGE_DIR"
    mkdir -p "$PACKAGE_DIR"

    peer lifecycle chaincode package \
        "$PACKAGE_FILE" \
        --path "$CHAINCODE_PATH" \
        --lang node \
        --label "$PACKAGE_LABEL"

    if [ ! -s "$PACKAGE_FILE" ]; then
        echo
        echo "ERROR: chaincode package was not created."
        exit 1
    fi

    echo
    echo "Package:"
    echo "  $PACKAGE_FILE"
}

# ============================================================
# Install
# ============================================================

install_chaincode()
{
    local peer="$1"

    echo
    echo "Installing ${CHAINCODE_NAME} on ${peer}..."

    set_peer_environment "$peer"

    peer lifecycle chaincode install \
        "$PACKAGE_FILE"

    echo "Installation request completed on ${peer}."
}

# ============================================================
# Package ID
# ============================================================

get_package_id()
{
    local peer="$1"

    set_peer_environment "$peer"

    peer lifecycle chaincode queryinstalled |
        awk -v label="$PACKAGE_LABEL" '
            index($0, label) {
                for (i = 1; i <= NF; i++) {
                    if ($i == "Package") {
                        print $(i + 2)
                        exit
                    }
                }
            }
        '
}

# ============================================================
# Approve
# ============================================================

approve_chaincode()
{
    local peer="$1"
    local channel="$2"
    local package_id="$3"

    echo
    echo "Approving ${CHAINCODE_NAME} for ${channel}..."
    echo "  Approving peer: ${peer}"

    set_peer_environment "$peer"

    peer lifecycle chaincode approveformyorg \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME" \
        --version "$CHAINCODE_VERSION" \
        --sequence "$CHAINCODE_SEQUENCE" \
        --package-id "$package_id" \
        --init-required \
        --orderer "$ORDERER_ENDPOINT" \
        --tls \
        --cafile "$ORDERER_TLS_CA"

    echo "Approval completed for ${channel}."
}

# ============================================================
# Commit
# ============================================================

commit_chaincode()
{
    local channel="$1"
    shift

    local first_peer=""
    local peer_args=()

    for peer in "$@"; do

        if [ -z "$first_peer" ]; then
            first_peer="$peer"
        fi

        local tls_ca
        tls_ca="$(peer_tls_ca "$peer")"

        peer_args+=(
            --peerAddresses "$(peer_address "$peer")"
            --tlsRootCertFiles "$tls_ca"
        )
    done

    if [ -z "$first_peer" ]; then
        echo "ERROR: no peers supplied for commit."
        return 1
    fi

    echo
    echo "Committing ${CHAINCODE_NAME} to ${channel}..."
    echo "  Peers:"

    for peer in "$@"; do
        echo "    ${peer}"
    done

    set_peer_environment "$first_peer"

    peer lifecycle chaincode commit \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME" \
        --version "$CHAINCODE_VERSION" \
        --sequence "$CHAINCODE_SEQUENCE" \
        --init-required \
        --orderer "$ORDERER_ENDPOINT" \
        --tls \
        --cafile "$ORDERER_TLS_CA" \
        "${peer_args[@]}"

    echo "Commit completed for ${channel}."
}

# ============================================================
# Verify
# ============================================================

verify_chaincode()
{
    local channel="$1"
    local peer="$2"

    echo
    echo "Verifying ${CHAINCODE_NAME} on ${channel}..."

    set_peer_environment "$peer"

    peer lifecycle chaincode querycommitted \
        --channelID "$channel" \
        --name "$CHAINCODE_NAME"
}

# ============================================================
# Main
# ============================================================

echo
echo "=============================================="
echo " VNFM Chaincode Lifecycle"
echo "=============================================="
echo

echo "Chaincode:"
echo "  Name:       ${CHAINCODE_NAME}"
echo "  Version:    ${CHAINCODE_VERSION}"
echo "  Sequence:   ${CHAINCODE_SEQUENCE}"

echo
echo "Topology:"
echo "  ${TOPOLOGY_FILE}"

echo
echo "Orderer:"
echo "  ${ORDERER_ENDPOINT}"

# ============================================================
# Package once
# ============================================================

package_chaincode

# ============================================================
# Discover channels
# ============================================================

mapfile -t CHANNELS < <(
    get_channels
)

if [ "${#CHANNELS[@]}" -eq 0 ]; then
    echo
    echo "ERROR: no channels found in topology."
    exit 1
fi

# ============================================================
# Process each channel
# ============================================================

for channel in "${CHANNELS[@]}"; do

    echo
    echo "=============================================="
    echo " Channel: ${channel}"
    echo "=============================================="

    mapfile -t PEERS < <(
        get_peers_for_channel "$channel"
    )

    if [ "${#PEERS[@]}" -eq 0 ]; then
        echo
        echo "ERROR: no peers found for ${channel}."
        exit 1
    fi

    echo
    echo "Peers:"
    for peer in "${PEERS[@]}"; do
        echo "  ${peer}"
    done

    # --------------------------------------------------------
    # Install on every peer belonging to this channel.
    # --------------------------------------------------------

    for peer in "${PEERS[@]}"; do
        install_chaincode "$peer"
    done

    # --------------------------------------------------------
    # Determine package ID from one participating peer.
    # --------------------------------------------------------

    PACKAGE_ID=""

    for peer in "${PEERS[@]}"; do

        PACKAGE_ID="$(get_package_id "$peer" || true)"

        if [ -n "$PACKAGE_ID" ]; then
            break
        fi

    done

    if [ -z "$PACKAGE_ID" ]; then
        echo
        echo "ERROR: unable to determine chaincode package ID."
        exit 1
    fi

    echo
    echo "Package ID:"
    echo "  ${PACKAGE_ID}"

    # --------------------------------------------------------
    # Approve VNFM's organization definition.
    # --------------------------------------------------------

    approve_chaincode \
        "${PEERS[0]}" \
        "$channel" \
        "$PACKAGE_ID"

    # --------------------------------------------------------
    # Commit definition to the channel.
    # --------------------------------------------------------

    commit_chaincode \
        "$channel" \
        "${PEERS[@]}"

    # --------------------------------------------------------
    # Verify.
    # --------------------------------------------------------

    verify_chaincode \
        "$channel" \
        "${PEERS[0]}"

done

echo
echo "=============================================="
echo " Chaincode lifecycle complete"
echo "=============================================="
echo