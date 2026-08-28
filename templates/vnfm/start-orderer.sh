#!/bin/bash

set -e

: "${VNFM_NAME:?VNFM_NAME is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${ORDERER_IP:?ORDERER_IP is required}"

ORDERER_NAME="fabric-orderer-1"

echo "=============================================="
echo " Starting nested Fabric orderer"
echo "=============================================="
echo
echo "Container : ${ORDERER_NAME}"
echo "XIT       : ${XIT_NETWORK}"
echo "IP        : ${ORDERER_IP}"
echo

# ------------------------------------------------------------
# Existing container
# ------------------------------------------------------------

if docker inspect "${ORDERER_NAME}" >/dev/null 2>&1; then

    RUNNING=$(docker inspect \
        --format '{{.State.Running}}' \
        "${ORDERER_NAME}")

    if [ "${RUNNING}" = "true" ]; then
        echo "Orderer container '${ORDERER_NAME}' is already running."
        exit 0
    fi

    echo "Orderer container exists but is stopped."
    echo "Starting '${ORDERER_NAME}'..."

    docker start "${ORDERER_NAME}"

    echo
    echo "Orderer container started."
    exit 0
fi

# ------------------------------------------------------------
# Create container
# ------------------------------------------------------------

docker run \
    -d \
    --name "${ORDERER_NAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${ORDERER_IP}" \
    --hostname "${ORDERER_NAME}" \
    hyperledger/fabric-orderer:2.5.16 \
    orderer

echo
echo "Nested Fabric orderer created and started."
echo