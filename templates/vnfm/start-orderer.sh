#!/bin/bash

set -e

: "${VNFM_NAME:?VNFM_NAME is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${CA_IP:?CA_IP is required}"
: "${ORDERER_IP:?ORDERER_IP is required}"
: "${VNFM_STATE_DIR:?VNFM_STATE_DIR is required}"
: "${HOST_ORDERER_DATA_DIR:?HOST_ORDERER_DATA_DIR is required}"

ORDERER_NAME="fabric-orderer-1"

CA_NAME="fabric-ca"
CA_PORT="7054"
CA_URL="http://${CA_NAME}:${CA_PORT}"
CA_MSP_ID="ca"

CA_CLIENT_IMAGE="hyperledger/fabric-ca:1.5.17"
ORDERER_IMAGE="hyperledger/fabric-orderer:2.5.16"

ORDERER_IDENTITY="orderer1"
ORDERER_PASSWORD="ordererpw"

CA_ADMIN_IDENTITY="admin"
CA_ADMIN_PASSWORD="adminpw"

ORDERER_HOME="/var/hyperledger/orderer"
ORDERER_MSP="${ORDERER_HOME}/msp"
ORDERER_LEDGER="${ORDERER_HOME}/production"

ORDERER_STATE_DIR="${VNFM_STATE_DIR}/orderer"

CA_CLIENT_NAME="fabric-ca-client-orderer"

echo "=============================================="
echo " Initializing nested Fabric orderer"
echo "=============================================="
echo
echo "Orderer       : ${ORDERER_NAME}"
echo "Orderer IP    : ${ORDERER_IP}"
echo "CA            : ${CA_NAME}:${CA_PORT}"
echo "XIT           : ${XIT_NETWORK}"
echo "Orderer state : ${ORDERER_STATE_DIR}"
echo "Host state    : ${HOST_ORDERER_DATA_DIR}"
echo

# ------------------------------------------------------------
# Remove old orderer/client containers
# ------------------------------------------------------------

if docker inspect "${ORDERER_NAME}" >/dev/null 2>&1; then
    echo "Removing existing orderer container..."
    docker rm -f "${ORDERER_NAME}" >/dev/null 2>&1 || true
fi

if docker inspect "${CA_CLIENT_NAME}" >/dev/null 2>&1; then
    echo "Removing existing CA client container..."
    docker rm -f "${CA_CLIENT_NAME}" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------
# Clean orderer state
# ------------------------------------------------------------

rm -rf "${ORDERER_STATE_DIR}"

mkdir -p \
    "${ORDERER_STATE_DIR}/admin" \
    "${ORDERER_STATE_DIR}/msp" \
    "${ORDERER_STATE_DIR}/production"

# ------------------------------------------------------------
# Enroll CA administrator
# ------------------------------------------------------------

echo
echo "----------------------------------------------"
echo " Enrolling CA administrator"
echo "----------------------------------------------"
echo

docker run \
    --name "${CA_CLIENT_NAME}" \
    --network "${XIT_NETWORK}" \
    --hostname "${CA_CLIENT_NAME}" \
    -e FABRIC_CA_CLIENT_HOME="/var/hyperledger/orderer/admin" \
    -v "${HOST_ORDERER_DATA_DIR}:/var/hyperledger/orderer" \
    "${CA_CLIENT_IMAGE}" \
    fabric-ca-client enroll \
        --caname "${CA_MSP_ID}" \
        -u "http://${CA_ADMIN_IDENTITY}:${CA_ADMIN_PASSWORD}@${CA_NAME}:${CA_PORT}" \
        -M "/var/hyperledger/orderer/admin/msp"

echo
echo "CA administrator enrolled."
echo

# ------------------------------------------------------------
# Register orderer identity
# ------------------------------------------------------------

echo "----------------------------------------------"
echo " Registering orderer identity"
echo "----------------------------------------------"
echo

docker run \
    --rm \
    --network "${XIT_NETWORK}" \
    --hostname "${CA_CLIENT_NAME}" \
    -e FABRIC_CA_CLIENT_HOME="/var/hyperledger/orderer/admin" \
    -v "${HOST_ORDERER_DATA_DIR}:/var/hyperledger/orderer" \
    "${CA_CLIENT_IMAGE}" \
    fabric-ca-client register \
        --caname "${CA_MSP_ID}" \
        --id.name "${ORDERER_IDENTITY}" \
        --id.secret "${ORDERER_PASSWORD}" \
        --id.type orderer \
        --id.affiliation "org1.orderer" \
        --mspdir "/var/hyperledger/orderer/admin/msp" \
        -u "${CA_URL}"

echo
echo "Orderer identity registered."
echo

# ------------------------------------------------------------
# Enroll orderer identity
# ------------------------------------------------------------

echo "----------------------------------------------"
echo " Enrolling orderer identity"
echo "----------------------------------------------"
echo

docker run \
    --rm \
    --network "${XIT_NETWORK}" \
    --hostname "${ORDERER_NAME}" \
    -e FABRIC_CA_CLIENT_HOME="${ORDERER_HOME}" \
    -v "${HOST_ORDERER_DATA_DIR}:${ORDERER_HOME}" \
    "${CA_CLIENT_IMAGE}" \
    fabric-ca-client enroll \
        --caname "${CA_MSP_ID}" \
        -u "http://${ORDERER_IDENTITY}:${ORDERER_PASSWORD}@${CA_NAME}:${CA_PORT}" \
        -M "${ORDERER_MSP}" \
        --csr.hosts "${ORDERER_NAME},${ORDERER_IP}"

echo
echo "Orderer MSP generated."
echo

# ------------------------------------------------------------
# Remove temporary client
# ------------------------------------------------------------

docker rm -f "${CA_CLIENT_NAME}" >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Verify MSP
# ------------------------------------------------------------

if [ ! -f "${ORDERER_STATE_DIR}/msp/signcerts/cert.pem" ]; then
    echo
    echo "ERROR: Orderer enrollment did not produce a certificate."
    exit 1
fi

if [ ! -d "${ORDERER_STATE_DIR}/msp/keystore" ]; then
    echo
    echo "ERROR: Orderer enrollment did not produce a keystore."
    exit 1
fi

echo
echo "Orderer MSP verified."
echo

# ------------------------------------------------------------
# Start orderer
# ------------------------------------------------------------

echo "----------------------------------------------"
echo " Starting Fabric orderer"
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
    -e ORDERER_GENERAL_LOCALMSPID="OrdererMSP" \
    -e ORDERER_GENERAL_LOCALMSPDIR="${ORDERER_HOME}/msp" \
    -e ORDERER_GENERAL_BOOTSTRAPMETHOD="none" \
    -e ORDERER_CHANNELPARTICIPATION_ENABLED="true" \
    -e ORDERER_GENERAL_TLS_ENABLED="false" \
    -e ORDERER_FILELEDGER_LOCATION="${ORDERER_LEDGER}" \
    -v "${HOST_ORDERER_DATA_DIR}:${ORDERER_HOME}" \
    "${ORDERER_IMAGE}" \
    orderer

echo
echo "Waiting for orderer to start..."
echo

for i in {1..30}; do

    if ! docker inspect "${ORDERER_NAME}" >/dev/null 2>&1; then
        echo "ERROR: Orderer container disappeared."
        exit 1
    fi

    RUNNING=$(docker inspect \
        --format '{{.State.Running}}' \
        "${ORDERER_NAME}")

    if [ "${RUNNING}" = "true" ]; then
        echo "Orderer container is running."
        break
    fi

    if [ "${i}" -eq 30 ]; then
        echo
        echo "ERROR: Orderer failed to start."
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
echo "MSP       : OrdererMSP"
echo