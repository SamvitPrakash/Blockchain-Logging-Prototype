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
CA_IMAGE="hyperledger/fabric-ca:1.5.17"
CA_PORT="7054"

ORDERER_HOME="/var/hyperledger/orderer"
ORDERER_MSP_DIR="${ORDERER_HOME}/msp"
ORDERER_TLS_DIR="${ORDERER_HOME}/tls"

ORDERER_MSP_ID="OrdererMSP"

ORDERER_PORT="7050"
ORDERER_CLUSTER_PORT="7051"

ORDERER_IDENTITY="orderer1"
ORDERER_PASSWORD="ordererpw"

ORDERER_TLS_IDENTITY="orderer1-tls"
ORDERER_TLS_PASSWORD="orderertlspw"

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
echo "FABRIC-BOOTSTRAP state      : ${ORDERER_STATE_DIR}"
echo "Host data       : ${HOST_ORDERER_DATA_DIR}"
echo

rm -rf "${ORDERER_STATE_DIR}"

mkdir -p \
    "${ORDERER_STATE_DIR}/msp" \
    "${ORDERER_STATE_DIR}/tls" \
    "${ORDERER_STATE_DIR}/production"

echo "----------------------------------------------"
echo " Enrolling CA administrator"
echo "----------------------------------------------"
echo

rm -rf "${HOST_ORDERER_DATA_DIR}/admin"

mkdir -p "${HOST_ORDERER_DATA_DIR}/admin"

docker run \
    --rm \
    --name "fabric-ca-client-orderer-admin" \
    --network "${XIT_NETWORK}" \
    -e FABRIC_CA_CLIENT_HOME="/tmp/fabric-ca-client" \
    -v "${HOST_ORDERER_DATA_DIR}/admin:/tmp/fabric-ca-client" \
    "${CA_IMAGE}" \
    fabric-ca-client enroll \
        -u "http://admin:adminpw@${CA_NAME}:${CA_PORT}"

echo
echo "CA administrator enrolled."
echo

echo "----------------------------------------------"
echo " Registering orderer identity"
echo "----------------------------------------------"
echo

docker run \
    --rm \
    --name "fabric-ca-client-orderer-register" \
    --network "${XIT_NETWORK}" \
    -e FABRIC_CA_CLIENT_HOME="/tmp/fabric-ca-client" \
    -v "${HOST_ORDERER_DATA_DIR}/admin:/tmp/fabric-ca-client" \
    "${CA_IMAGE}" \
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

docker run \
    --rm \
    --name "fabric-ca-client-orderer-enroll" \
    --network "${XIT_NETWORK}" \
    -e FABRIC_CA_CLIENT_HOME="/tmp/fabric-ca-client" \
    -v "${HOST_ORDERER_DATA_DIR}:${ORDERER_HOME}" \
    "${CA_IMAGE}" \
    fabric-ca-client enroll \
        -u "http://${ORDERER_IDENTITY}:${ORDERER_PASSWORD}@${CA_NAME}:${CA_PORT}" \
        -M "${ORDERER_MSP_DIR}"

echo
echo "Orderer MSP generated."
echo

echo "----------------------------------------------"
echo " Registering orderer TLS identity"
echo "----------------------------------------------"
echo

docker run \
    --rm \
    --name "fabric-ca-client-orderer-tls-register" \
    --network "${XIT_NETWORK}" \
    -e FABRIC_CA_CLIENT_HOME="/tmp/fabric-ca-client" \
    -v "${HOST_ORDERER_DATA_DIR}/admin:/tmp/fabric-ca-client" \
    "${CA_IMAGE}" \
    fabric-ca-client register \
        --id.name "${ORDERER_TLS_IDENTITY}" \
        --id.secret "${ORDERER_TLS_PASSWORD}" \
        --id.type orderer \
        --id.affiliation "org1.orderer" \
        -u "http://${CA_NAME}:${CA_PORT}"

echo
echo "Orderer TLS identity registered."
echo

echo "----------------------------------------------"
echo " Enrolling orderer TLS identity"
echo "----------------------------------------------"
echo

docker run \
    --rm \
    --name "fabric-ca-client-orderer-tls-enroll" \
    --network "${XIT_NETWORK}" \
    -e FABRIC_CA_CLIENT_HOME="/tmp/fabric-ca-client" \
    -v "${HOST_ORDERER_DATA_DIR}:${ORDERER_HOME}" \
    "${CA_IMAGE}" \
    fabric-ca-client enroll \
        -u "http://${ORDERER_TLS_IDENTITY}:${ORDERER_TLS_PASSWORD}@${CA_NAME}:${CA_PORT}" \
        -M "${ORDERER_TLS_DIR}" \
        --enrollment.profile tls \
        --csr.hosts "${ORDERER_NAME},${ORDERER_IP},localhost"

echo
echo "Orderer TLS material generated."
echo

TLS_CERT=$(find "${ORDERER_STATE_DIR}/tls/signcerts" \
    -type f \
    -print \
    -quit)

TLS_KEY=$(find "${ORDERER_STATE_DIR}/tls/keystore" \
    -type f \
    -print \
    -quit)

TLS_CA=$(find "${ORDERER_STATE_DIR}/tls/tlscacerts" \
    -type f \
    -print \
    -quit)

if [ -z "${TLS_CERT}" ]; then
    echo "ERROR: TLS certificate was not generated."
    exit 1
fi

if [ -z "${TLS_KEY}" ]; then
    echo "ERROR: TLS private key was not generated."
    exit 1
fi

if [ -z "${TLS_CA}" ]; then
    echo "ERROR: TLS CA certificate was not generated."
    exit 1
fi

echo "TLS certificate : ${TLS_CERT}"
echo "TLS private key : ${TLS_KEY}"
echo "TLS CA          : ${TLS_CA}"

cp "${TLS_CERT}" "${ORDERER_STATE_DIR}/tls/server.crt"
cp "${TLS_KEY}" "${ORDERER_STATE_DIR}/tls/server.key"
cp "${TLS_CA}" "${ORDERER_STATE_DIR}/tls/ca.crt"

echo
echo "TLS material normalized."
echo

echo "----------------------------------------------"
echo " Configuring Orderer local MSP"
echo "----------------------------------------------"
echo

cat > "${ORDERER_STATE_DIR}/msp/config.yaml" <<'EOF'
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    OrganizationalUnitIdentifier: client

  AdminOUIdentifier:
    OrganizationalUnitIdentifier: admin

  PeerOUIdentifier:
    OrganizationalUnitIdentifier: peer

  OrdererOUIdentifier:
    OrganizationalUnitIdentifier: orderer
EOF

echo "Orderer MSP config created."
echo

mkdir -p "${ORDERER_STATE_DIR}/msp/tlscacerts"

cp \
    "${ORDERER_STATE_DIR}/tls/ca.crt" \
    "${ORDERER_STATE_DIR}/msp/tlscacerts/ca.crt"

if [ ! -f "${ORDERER_STATE_DIR}/msp/signcerts/cert.pem" ]; then
    echo "ERROR: Orderer sign certificate was not generated."
    exit 1
fi

if ! find "${ORDERER_STATE_DIR}/msp/keystore" \
    -type f \
    -print \
    -quit | grep -q .
then
    echo "ERROR: Orderer private key was not generated."
    exit 1
fi

if [ ! -f "${ORDERER_STATE_DIR}/msp/config.yaml" ]; then
    echo "ERROR: Orderer MSP config.yaml was not generated."
    exit 1
fi

if [ ! -f "${ORDERER_STATE_DIR}/tls/server.crt" ]; then
    echo "ERROR: Orderer TLS certificate was not generated."
    exit 1
fi

if [ ! -f "${ORDERER_STATE_DIR}/tls/server.key" ]; then
    echo "ERROR: Orderer TLS private key was not generated."
    exit 1
fi

if [ ! -f "${ORDERER_STATE_DIR}/tls/ca.crt" ]; then
    echo "ERROR: Orderer TLS CA certificate was not generated."
    exit 1
fi

echo "Orderer MSP verified."
echo "Orderer TLS verified."
echo

echo "----------------------------------------------"
echo " Starting nested Fabric orderer"
echo "----------------------------------------------"
echo

docker rm -f "${ORDERER_NAME}" >/dev/null 2>&1 || true

docker run \
    -d \
    --name "${ORDERER_NAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${ORDERER_IP}" \
    --hostname "${ORDERER_NAME}" \
    -e FABRIC_CFG_PATH="/etc/hyperledger/fabric" \
    -e ORDERER_GENERAL_LISTENADDRESS="0.0.0.0" \
    -e ORDERER_GENERAL_LISTENPORT="${ORDERER_PORT}" \
    -e ORDERER_GENERAL_LOCALMSPID="${ORDERER_MSP_ID}" \
    -e ORDERER_GENERAL_LOCALMSPDIR="${ORDERER_HOME}/msp" \
    -e ORDERER_GENERAL_BOOTSTRAPMETHOD="none" \
    -e ORDERER_CHANNELPARTICIPATION_ENABLED="true" \
    -e ORDERER_GENERAL_TLS_ENABLED="true" \
    -e ORDERER_GENERAL_TLS_PRIVATEKEY="${ORDERER_HOME}/tls/server.key" \
    -e ORDERER_GENERAL_TLS_CERTIFICATE="${ORDERER_HOME}/tls/server.crt" \
    -e ORDERER_GENERAL_TLS_ROOTCAS="[${ORDERER_HOME}/tls/ca.crt]" \
    -e ORDERER_GENERAL_CLUSTER_LISTENADDRESS="0.0.0.0" \
    -e ORDERER_GENERAL_CLUSTER_LISTENPORT="${ORDERER_CLUSTER_PORT}" \
    -e ORDERER_GENERAL_CLUSTER_SERVERCERTIFICATE="${ORDERER_HOME}/tls/server.crt" \
    -e ORDERER_GENERAL_CLUSTER_SERVERPRIVATEKEY="${ORDERER_HOME}/tls/server.key" \
    -e ORDERER_GENERAL_CLUSTER_ROOTCAS="[${ORDERER_HOME}/tls/ca.crt]" \
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
echo "Port      : ${ORDERER_PORT}"
echo "Cluster   : ${ORDERER_CLUSTER_PORT}"
echo "MSP ID    : ${ORDERER_MSP_ID}"
echo "TLS       : enabled"
echo