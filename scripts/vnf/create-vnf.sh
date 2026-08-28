#!/bin/bash

set -euo pipefail

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi


# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CHANNEL_TX="$PROJECT_ROOT/vnf-manager/config/xit-channel.tx"
ORG_ADMIN_MSP="$PROJECT_ROOT/vnf-manager/identities/org-admin/msp"
BUILD_DIR="$PROJECT_ROOT/build"

VNF_TEMPLATE="$PROJECT_ROOT/templates/vnf/compose.yaml"

VNF_BUILD_DIR="$BUILD_DIR/vnf-${INSTANCE}"

IDENTITY_DIR="$PROJECT_ROOT/vnf-manager/identities/peers/peer-vnf-${INSTANCE}"


# ------------------------------------------------------------
# Network configuration
# ------------------------------------------------------------

XIT_NETWORK="XIT"

# XIT currently uses:
#
#   172.20.0.0/16
#
# Existing infrastructure:
#
#   172.20.0.2 = Fabric CA
#   172.20.0.3 = Orderer
#   172.20.0.4 = existing peer
#
# Therefore VNF peers begin at .5.
#
VNF_XIT_IP="172.20.0.$((INSTANCE + 10))"

OAM_NETWORK="OAM-${INSTANCE}"

# Each VNF gets its own OAM address.
#
# Example:
#
#   VNF 1 -> 10.20.1.3
#   VNF 2 -> 10.20.2.3
#   VNF 3 -> 10.20.3.3
#
VNF_OAM_IP="10.20.${INSTANCE}.3"


# ------------------------------------------------------------
# Container configuration
# ------------------------------------------------------------

VNF_CONTAINER="vnf_${INSTANCE}"

PEER_NAME="peer-vnf-${INSTANCE}"

PEER_PORT="7051"

CHAINCODE_PORT="7052"


# ------------------------------------------------------------
# Validate template
# ------------------------------------------------------------

if [ ! -f "$VNF_TEMPLATE" ]; then
    echo "Error: VNF template not found:"
    echo "  $VNF_TEMPLATE"
    exit 1
fi


# ------------------------------------------------------------
# Validate identity
# ------------------------------------------------------------

if [ ! -d "$IDENTITY_DIR" ]; then
    echo "Error: Fabric peer identity does not exist:"
    echo "  $IDENTITY_DIR"
    echo
    echo "Create the peer identity first with:"
    echo
    echo "  ./scripts/vnf/create-peer-identity.sh ${INSTANCE}"
    exit 1
fi

if [ ! -f "$IDENTITY_DIR/msp/signcerts/cert.pem" ]; then
    echo "Error: peer MSP certificate not found:"
    echo "  $IDENTITY_DIR/msp/signcerts/cert.pem"
    exit 1
fi

if [ ! -f "$IDENTITY_DIR/msp/config.yaml" ]; then
    echo "Error: peer MSP config.yaml not found:"
    echo "  $IDENTITY_DIR/msp/config.yaml"
    exit 1
fi

if [ ! -f "$IDENTITY_DIR/tls/signcerts/cert.pem" ]; then
    echo "Error: peer TLS certificate not found:"
    echo "  $IDENTITY_DIR/tls/signcerts/cert.pem"
    exit 1
fi


# ------------------------------------------------------------
# Discover TLS private key
# ------------------------------------------------------------

TLS_KEY=$(find "$IDENTITY_DIR/tls/keystore" \
    -maxdepth 1 \
    -type f \
    -name '*_sk' \
    -print -quit)

if [ -z "$TLS_KEY" ]; then
    echo "Error: Fabric peer TLS private key not found."
    echo
    echo "Expected a key inside:"
    echo "  $IDENTITY_DIR/tls/keystore"
    exit 1
fi

TLS_KEY_NAME="$(basename "$TLS_KEY")"


# ------------------------------------------------------------
# Check XIT network
# ------------------------------------------------------------

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT Docker network does not exist."
    echo
    echo "Create the XIT network first."
    exit 1
fi


# ------------------------------------------------------------
# Check XIT subnet
# ------------------------------------------------------------

XIT_SUBNET=$(docker network inspect "$XIT_NETWORK" \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')

if [ "$XIT_SUBNET" != "172.20.0.0/16" ]; then
    echo "Error: unexpected XIT subnet."
    echo
    echo "Expected:"
    echo "  172.20.0.0/16"
    echo
    echo "Found:"
    echo "  ${XIT_SUBNET:-none}"
    echo
    echo "Update the generator before creating VNF instances."
    exit 1
fi


# ------------------------------------------------------------
# Check OAM network
# ------------------------------------------------------------

if ! docker network inspect "$OAM_NETWORK" >/dev/null 2>&1; then
    echo "Error: OAM network '${OAM_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    exit 1
fi


# ------------------------------------------------------------
# Check for duplicate VNF
# ------------------------------------------------------------

if [ -d "$VNF_BUILD_DIR" ]; then
    echo "Error: VNF instance ${INSTANCE} already exists."
    echo
    echo "Existing directory:"
    echo "  $VNF_BUILD_DIR"
    exit 1
fi


# ------------------------------------------------------------
# Discover existing VNF peers
# ------------------------------------------------------------

VNF_PEERS=""

for VNF_DIR in "$BUILD_DIR"/vnf-*; do

    [ -d "$VNF_DIR" ] || continue

    PEER_INSTANCE="${VNF_DIR##*-}"

    # Ignore non-numeric directories
    if ! [[ "$PEER_INSTANCE" =~ ^[0-9]+$ ]]; then
        continue
    fi

    # Ignore the VNF currently being created
    if [ "$PEER_INSTANCE" = "$INSTANCE" ]; then
        continue
    fi

    PEER_IP="172.20.0.$((PEER_INSTANCE + 10))"

    if [ -z "$VNF_PEERS" ]; then
        VNF_PEERS="$PEER_IP"
    else
        VNF_PEERS="${VNF_PEERS},${PEER_IP}"
    fi

done


# ------------------------------------------------------------
# Create VNF build directory
# ------------------------------------------------------------

mkdir -p "$VNF_BUILD_DIR"


# ------------------------------------------------------------
# Export variables for envsubst
# ------------------------------------------------------------

export VNF_CONTAINER
export PEER_NAME

export VNF_XIT_IP
export VNF_OAM_IP

export OAM_NETWORK
export XIT_NETWORK

export IDENTITY_DIR
export TLS_KEY_NAME

export PEER_PORT
export CHAINCODE_PORT
export ORG_ADMIN_MSP
export VNF_PEERS
export CHANNEL_TX


# ------------------------------------------------------------
# Generate Docker Compose
# ------------------------------------------------------------

envsubst < "$VNF_TEMPLATE" \
    > "$VNF_BUILD_DIR/compose.yaml"


# ------------------------------------------------------------
# Validate generated Compose
# ------------------------------------------------------------

docker compose \
    -f "$VNF_BUILD_DIR/compose.yaml" \
    config >/dev/null


# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

echo
echo "=============================================="
echo " VNF instance ${INSTANCE} created successfully"
echo "=============================================="
echo

echo "Container:"
echo "  ${VNF_CONTAINER}"

echo

echo "Fabric peer:"
echo "  ${PEER_NAME}"

echo

echo "Identity:"
echo "  ${IDENTITY_DIR}"

echo

echo "XIT:"
echo "  Network : ${XIT_NETWORK}"
echo "  IP      : ${VNF_XIT_IP}"

echo

echo "OAM:"
echo "  Network : ${OAM_NETWORK}"
echo "  IP      : ${VNF_OAM_IP}"

echo

echo "Peer:"
echo "  Port      : ${PEER_PORT}"
echo "  Chaincode : ${CHAINCODE_PORT}"

echo

echo "Known VNF peers:"
echo "  ${VNF_PEERS:-none}"

echo

echo "Generated:"
echo "  ${VNF_BUILD_DIR}/compose.yaml"

echo