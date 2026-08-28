#!/bin/bash

set -e

: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_IP:?PEER_IP is required}"
: "${PEER_HOSTNAME:?PEER_HOSTNAME is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${CA_IP:?CA_IP is required}"

PEER_IMAGE="hyperledger/fabric-peer:2.5"

PEER_STATE_DIR="${VNF_STATE_DIR}/peer"
PEER_MSP_DIR="${PEER_STATE_DIR}/msp"
PEER_TLS_DIR="${PEER_STATE_DIR}/tls"

echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="
echo
echo "Peer         : ${PEER_NAME}"
echo "XIT          : ${XIT_NETWORK}"
echo "Peer IP      : ${PEER_IP}"
echo "CA IP        : ${CA_IP}"
echo

# ------------------------------------------------------------
# Verify identity material
# ------------------------------------------------------------

if [ ! -f "${PEER_MSP_DIR}/signcerts/cert.pem" ]; then
    echo "Error: peer MSP has not been enrolled."
    echo
    echo "Run:"
    echo "  /opt/vnf/enroll-peer.sh"
    exit 1
fi

if [ ! -f "${PEER_TLS_DIR}/server.crt" ]; then
    echo "Error: peer TLS certificate does not exist."
    exit 1
fi

if [ ! -f "${PEER_TLS_DIR}/server.key" ]; then
    echo "Error: peer TLS private key does not exist."
    exit 1
fi

if [ ! -f "${PEER_TLS_DIR}/ca.crt" ]; then
    echo "Error: peer TLS CA certificate does not exist."
    exit 1
fi

# ------------------------------------------------------------
# Remove old stopped container
# ------------------------------------------------------------

if docker inspect "${PEER_NAME}" >/dev/null 2>&1; then

    RUNNING="$(docker inspect \
        --format '{{.State.Running}}' \
        "${PEER_NAME}")"

    if [ "${RUNNING}" = "true" ]; then
        echo "Peer '${PEER_NAME}' is already running."
        exit 0
    fi

    docker rm "${PEER_NAME}"
fi

# ------------------------------------------------------------
# Start peer
# ------------------------------------------------------------

docker run \
    -d \
    --name "${PEER_NAME}" \
    --hostname "${PEER_HOSTNAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${PEER_IP}" \
    -e CORE_PEER_ID="${PEER_NAME}" \
    -e CORE_PEER_ADDRESS="${PEER_HOSTNAME}:7051" \
    -e CORE_PEER_LISTENADDRESS="0.0.0.0:7051" \
    -e CORE_PEER_CHAINCODEADDRESS="${PEER_HOSTNAME}:7052" \
    -e CORE_PEER_CHAINCODELISTENADDRESS="0.0.0.0:7052" \
    -e CORE_PEER_LOCALMSPID="Org1MSP" \
    -e CORE_PEER_MSPCONFIGPATH="/etc/hyperledger/fabric/msp" \
    -e CORE_PEER_TLS_ENABLED="true" \
    -e CORE_PEER_TLS_CERT_FILE="/etc/hyperledger/fabric/tls/server.crt" \
    -e CORE_PEER_TLS_KEY_FILE="/etc/hyperledger/fabric/tls/server.key" \
    -e CORE_PEER_TLS_ROOTCERT_FILE="/etc/hyperledger/fabric/tls/ca.crt" \
    -v "${PEER_MSP_DIR}:/etc/hyperledger/fabric/msp:ro" \
    -v "${PEER_TLS_DIR}:/etc/hyperledger/fabric/tls:ro" \
    "${PEER_IMAGE}" \
    peer node start

sleep 2

RUNNING="$(docker inspect \
    --format '{{.State.Running}}' \
    "${PEER_NAME}")"

if [ "${RUNNING}" != "true" ]; then
    echo
    echo "ERROR: Fabric peer exited during startup."
    echo
    docker logs "${PEER_NAME}"
    exit 1
fi

echo
echo "Nested Fabric peer is running."
echo
