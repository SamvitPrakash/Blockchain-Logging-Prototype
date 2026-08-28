#!/bin/bash

set -e

: "${VNF_INSTANCE:?VNF_INSTANCE is required}"
: "${VNF_NAME:?VNF_NAME is required}"
: "${OAM_NETWORK:?OAM_NETWORK is required}"
: "${OAM_IP:?OAM_IP is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${PEER_IP:?PEER_IP is required}"

PEER_NAME="fabric-peer-${VNF_INSTANCE}"

echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="
echo
echo "Peer         : ${PEER_NAME}"
echo "VNF          : ${VNF_NAME}"
echo "XIT          : ${XIT_NETWORK}"
echo "Peer IP      : ${PEER_IP}"
echo

# ------------------------------------------------------------
# Existing container
# ------------------------------------------------------------

if docker inspect "${PEER_NAME}" >/dev/null 2>&1; then

    RUNNING=$(docker inspect \
        --format '{{.State.Running}}' \
        "${PEER_NAME}")

    if [ "${RUNNING}" = "true" ]; then
        echo "Peer container '${PEER_NAME}' is already running."
        exit 0
    fi

    echo "Peer container exists but is stopped."
    echo "Starting '${PEER_NAME}'..."

    docker start "${PEER_NAME}"

    echo
    echo "Peer container started."
    exit 0
fi

# ------------------------------------------------------------
# Create container
# ------------------------------------------------------------

docker run \
    -d \
    --name "${PEER_NAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${PEER_IP}" \
    --hostname "${PEER_NAME}" \
    -e FABRIC_LOGGING_SPEC=INFO \
    -e CORE_PEER_ID="${PEER_NAME}" \
    -e CORE_PEER_ADDRESS="${PEER_NAME}:7051" \
    -e CORE_PEER_LISTENADDRESS="0.0.0.0:7051" \
    -e CORE_PEER_CHAINCODEADDRESS="${PEER_NAME}:7052" \
    -e CORE_PEER_CHAINCODELISTENADDRESS="0.0.0.0:7052" \
    -e CORE_PEER_TLS_ENABLED=true \
    hyperledger/fabric-peer:2.5

echo
echo "Nested Fabric peer created and started."
echo