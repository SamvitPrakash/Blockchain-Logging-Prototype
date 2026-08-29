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

ORDERER_HOME="/var/hyperledger/orderer"
ORDERER_MSP_DIR="${ORDERER_HOME}/msp"
ORDERER_TLS_DIR="${ORDERER_HOME}/tls"

ORDERER_MSP_ID="OrdererMSP"

ORDERER_IDENTITY="orderer1"
ORDERER_PASSWORD="ordererpw"

ORDERER_TLS_IDENTITY="orderer1-tls"
ORDERER_TLS_PASSWORD="orderertlspw"

ORDERER_STATE_DIR="${VNFM_STATE_DIR}/orderer"

CA_URL="http://${CA_NAME}:${CA_PORT}"

echo "=============================================="
echo " Initializing Fabric orderer identity"
echo "=============================================="
echo
echo "Orderer          : ${ORDERER_NAME}"
echo "XIT              : ${XIT_NETWORK}"
echo "IP               : ${ORDERER_IP}"
echo "CA               : ${CA_NAME}:${CA_PORT}"
echo "Bootstrap state  : ${ORDERER_STATE_DIR}"
echo "Host data        : ${HOST_ORDERER_DATA_DIR}"
echo

# ============================================================
# Prepare orderer state
# ============================================================

rm -rf "${ORDERER_STATE_DIR}"

mkdir -p \
    "${ORDERER_STATE_DIR}/msp" \
    "${ORDERER_STATE_DIR}/tls" \
    "${ORDERER_STATE_DIR}/production"

# ============================================================
# Wait for Fabric CA
# ============================================================

echo "----------------------------------------------"
echo " Waiting for Fabric CA"
echo "----------------------------------------------"
echo

CA_READY=0

for i in {1..30}; do

    if fabric-ca-client getcainfo \
        -u "${CA_URL}" \
        --caname ca \
        >/dev/null 2>&1
    then
        CA_READY=1
        echo "Fabric CA is ready."
        break
    fi

    echo "Waiting for Fabric CA... (${i}/30)"
    sleep 1
done

if [ "${CA_READY}" -ne 1 ]; then
    echo
    echo "ERROR: Fabric CA did not become ready."
    exit 1
fi

echo

# ============================================================
# Enroll CA administrator
# ============================================================

echo "----------------------------------------------"
echo " Enrolling CA administrator"
echo "----------------------------------------------"
echo

rm -rf "${HOST_ORDERER_DATA_DIR}/admin"

mkdir -p "${HOST_ORDERER_DATA_DIR}/admin"

export FABRIC_CA_CLIENT_HOME="${HOST_ORDERER_DATA_DIR}/admin"

fabric-ca-client enroll \
    -u "http://admin:adminpw@${CA_NAME}:${CA_PORT}"

echo
echo "CA administrator enrolled."
echo

# ============================================================
# Register orderer identity
# ============================================================

echo "----------------------------------------------"
echo " Registering orderer identity"
echo "----------------------------------------------"
echo

fabric-ca-client register \
    --id.name "${ORDERER_IDENTITY}" \
    --id.secret "${ORDERER_PASSWORD}" \
    --id.type orderer \
    --id.affiliation "org1.orderer" \
    -u "${CA_URL}"

echo
echo "Orderer identity registered."
echo

# ============================================================
# Enroll orderer identity
# ============================================================

echo "----------------------------------------------"
echo " Enrolling orderer identity"
echo "----------------------------------------------"
echo

export FABRIC_CA_CLIENT_HOME="${ORDERER_STATE_DIR}/msp"

fabric-ca-client enroll \
    -u "http://${ORDERER_IDENTITY}:${ORDERER_PASSWORD}@${CA_NAME}:${CA_PORT}" \
    -M "${ORDERER_MSP_DIR}"

echo
echo "Orderer MSP generated."
echo

# ============================================================
# Register TLS identity
# ============================================================

echo "----------------------------------------------"
echo " Registering orderer TLS identity"
echo "----------------------------------------------"
echo

export FABRIC_CA_CLIENT_HOME="${HOST_ORDERER_DATA_DIR}/admin"

fabric-ca-client register \
    --id.name "${ORDERER_TLS_IDENTITY}" \
    --id.secret "${ORDERER_TLS_PASSWORD}" \
    --id.type orderer \
    --id.affiliation "org1.orderer" \
    -u "${CA_URL}"

echo
echo "Orderer TLS identity registered."
echo

# ============================================================
# Enroll TLS identity
# ============================================================

echo "----------------------------------------------"
echo " Enrolling orderer TLS identity"
echo "----------------------------------------------"
echo

export FABRIC_CA_CLIENT_HOME="${ORDERER_STATE_DIR}/tls"

fabric-ca-client enroll \
    -u "http://${ORDERER_TLS_IDENTITY}:${ORDERER_TLS_PASSWORD}@${CA_NAME}:${CA_PORT}" \
    -M "${ORDERER_TLS_DIR}" \
    --enrollment.profile tls \
    --csr.hosts "${ORDERER_NAME},${ORDERER_IP},localhost"

echo
echo "Orderer TLS material generated."
echo

# ============================================================
# Normalize TLS material
# ============================================================

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

# ============================================================
# Configure Orderer local MSP
# ============================================================

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

# ============================================================
# Validate generated material
# ============================================================

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

# ============================================================
# Bootstrap complete
# ============================================================

echo "=============================================="
echo " Orderer identity initialization complete"
echo "=============================================="
echo
echo "Orderer state : ${ORDERER_STATE_DIR}"
echo "MSP           : ${ORDERER_STATE_DIR}/msp"
echo "TLS           : ${ORDERER_STATE_DIR}/tls"
echo
echo "The orderer itself is NOT started here."
echo "Docker Compose will start it after bootstrap exits."
echo