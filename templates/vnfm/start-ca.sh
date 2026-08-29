#!/bin/bash

set -e

: "${VNFM_NAME:?VNFM_NAME is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${CA_IP:?CA_IP is required}"
: "${VNFM_STATE_DIR:?VNFM_STATE_DIR is required}"
: "${HOST_CA_DATA_DIR:?HOST_CA_DATA_DIR is required}"

CA_NAME="fabric-ca"
CA_IMAGE="hyperledger/fabric-ca:1.5.17"

CA_CONTAINER_DATA_DIR="/etc/hyperledger/fabric-ca-server"
CA_CONFIG="${CA_CONTAINER_DATA_DIR}/fabric-ca-server-config.yaml"
CA_STATE_DIR="${VNFM_STATE_DIR}/ca"

echo "=============================================="
echo " Starting nested Fabric CA"
echo "=============================================="
echo
echo "Container       : ${CA_NAME}"
echo "Image           : ${CA_IMAGE}"
echo "XIT             : ${XIT_NETWORK}"
echo "IP              : ${CA_IP}"
echo "VNFM state      : ${CA_STATE_DIR}"
echo "Host data       : ${HOST_CA_DATA_DIR}"
echo

if [ ! -d "${CA_STATE_DIR}" ]; then
    echo "Error: CA state directory does not exist:"
    echo "  ${CA_STATE_DIR}"
    exit 1
fi

if [ ! -f "${CA_STATE_DIR}/fabric-ca-server-config.yaml" ]; then
    echo "Error: CA configuration does not exist:"
    echo "  ${CA_STATE_DIR}/fabric-ca-server-config.yaml"
    exit 1
fi

docker run \
    -d \
    --name "${CA_NAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${CA_IP}" \
    --hostname "${CA_NAME}" \
    -e FABRIC_CA_HOME="${CA_CONTAINER_DATA_DIR}" \
    -v "${HOST_CA_DATA_DIR}:${CA_CONTAINER_DATA_DIR}" \
    "${CA_IMAGE}" \
    fabric-ca-server start \
        -c "${CA_CONFIG}" \
        -b admin:adminpw

echo
echo "Waiting for Fabric CA initialization..."

for i in {1..30}; do
    if docker logs "${CA_NAME}" 2>&1 | grep -q "Listening on"; then
        echo "Fabric CA is listening."
        break
    fi

    if [ "${i}" -eq 30 ]; then
        echo
        echo "Error: Fabric CA failed to become ready."
        echo
        docker logs "${CA_NAME}" 2>&1 || true
        exit 1
    fi

    sleep 1
done

echo
echo "Fabric CA started."
echo