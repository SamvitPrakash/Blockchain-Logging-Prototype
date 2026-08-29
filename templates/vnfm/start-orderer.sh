#!/bin/bash

set -e

: "${VNFM_NAME:?VNFM_NAME is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${CA_IP:?CA_IP is required}"
: "${ORDERER_IP:?ORDERER_IP is required}"
: "${VNFM_STATE_DIR:?VNFM_STATE_DIR is required}"
: "${HOST_ORDERER_DATA_DIR:?HOST_ORDERER_DATA_DIR is required}"

ORDERER_NAME="fabric-orderer-1"
ORDERER_IMAGE="hyperledger/fabric-orderer:2.5.16"

CA_NAME="fabric-ca"
CA_PORT="7054"

ORDERER_HOME="/var/hyperledger/orderer"
ORDERER_MSP_DIR="${ORDERER_HOME}/msp"
ORDERER_LEDGER_DIR="${ORDERER_HOME}/production"
ORDERER_MSP_ID="OrdererMSP"

ORDERER_IDENTITY="orderer1"
ORDERER_PASSWORD="ordererpw"

ORDERER_STATE_DIR="${VNFM_STATE_DIR}/orderer"

echo "=============================================="
echo " Initializing nested Fabric orderer"
echo "=============================================="
echo
echo "Container       : ${ORDERER_NAME}"
echo "Image           : ${ORDERER_IMAGE}"
echo "XIT             : ${XIT_NETWORK}"
echo "IP              : ${ORDERER_IP}"
echo "CA              : ${CA_NAME}:${CA_PORT}"
echo "VNFM state      : ${ORDERER_STATE_DIR}"
echo "Host data       : ${HOST_ORDERER_DATA_DIR}"
echo

mkdir -p \
    "${ORDERER_STATE_DIR}/msp" \
    "${ORDERER_STATE_DIR}/production"

echo "----------------------------------------------"
echo " Registering orderer identity"
echo "----------------------------------------------"
echo

docker exec "${CA_NAME}" \
    fabric-ca-client register \
        --id.name "${ORDERER_IDENTITY}" \
        --id.secret "${ORDERER_PASSWORD}" \
        --id.type orderer \
        --id.affiliation "org1.orderer" \
        -u "http://${CA_NAME}:${CA_PORT}"

echo
echo "Orderer identity registered."
echo

echo "----------------------------------------------"
echo " Enrolling orderer identity"
echo "----------------------------------------------"
echo

docker exec "${CA_NAME}" \
    fabric-ca-client enroll \
        -u "http://${ORDERER_IDENTITY}:${ORDERER_PASSWORD}@${CA_NAME}:${CA_PORT}" \
        -M "${ORDERER_MSP_DIR}"

echo
echo "Orderer MSP generated."
echo

echo "----------------------------------------------"
echo " Starting nested Fabric orderer"
echo "----------------------------------------------"
echo

docker run \
    -d \
    --name "${ORDERER_NAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${ORDERER_IP}" \
    --hostname "${ORDERER_NAME}" \
    -e FABRIC_CFG_PATH="/etc/hyperledger/fabric" \
    -e ORDERER_GENERAL_LISTENADDRESS="0.0.0.0" \
    -e ORDERER_GENERAL_LISTENPORT="7050" \
    -e ORDERER_GENERAL_LOCALMSPID="${ORDERER_MSP_ID}" \
    -e ORDERER_GENERAL_LOCALMSPDIR="${ORDERER_HOME}/msp" \
    -e ORDERER_GENERAL_BOOTSTRAPMETHOD="none" \
    -e ORDERER_CHANNELPARTICIPATION_ENABLED="true" \
    -e ORDERER_GENERAL_TLS_ENABLED="false" \
    -e ORDERER_FILELEDGER_LOCATION="${ORDERER_HOME}/production" \
    -v "${HOST_ORDERER_DATA_DIR}:${ORDERER_HOME}" \
    "${ORDERER_IMAGE}" \
    orderer

echo
echo "Waiting for Fabric orderer..."

for i in {1..30}; do

    if ! docker inspect "${ORDERER_NAME}" >/dev/null 2>&1; then
        echo "Error: orderer container disappeared."
        exit 1
    fi

    RUNNING=$(docker inspect \
        --format '{{.State.Running}}' \
        "${ORDERER_NAME}")

    if [ "${RUNNING}" = "true" ]; then
        echo "Fabric orderer is running."
        break
    fi

    if [ "${i}" -eq 30 ]; then
        echo
        echo "Error: Fabric orderer failed to start."
        echo
        docker logs "${ORDERER_NAME}" 2>&1 || true
        exit 1
    fi

    sleep 1
done

echo
echo "=============================================="
echo " Fabric orderer started"
echo "=============================================="
echo
echo "Container : ${ORDERER_NAME}"
echo "IP        : ${ORDERER_IP}"
echo "Port      : 7050"
echo "MSP ID    : ${ORDERER_MSP_ID}"
echo