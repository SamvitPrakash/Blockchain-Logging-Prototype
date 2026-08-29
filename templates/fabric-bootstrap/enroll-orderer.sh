#!/bin/bash

set -e

: "${CA_IP:?CA_IP is required}"
: "${ORDERER_IP:?ORDERER_IP is required}"
: "${VNFM_STATE_DIR:?VNFM_STATE_DIR is required}"

CA_NAME="fabric-ca"
CA_PORT="7054"

ORDERER_NAME="fabric-orderer-1"

ORDERER_IDENTITY="orderer1"
ORDERER_PASSWORD="ordererpw"

ORDERER_TLS_IDENTITY="orderer1-tls"
ORDERER_TLS_PASSWORD="orderertlspw"

ORDERER_STATE_DIR="${VNFM_STATE_DIR}/orderer"

CA_URL="http://${CA_NAME}:${CA_PORT}"

ORDERER_MSP_DIR="${ORDERER_STATE_DIR}/msp"
ORDERER_TLS_DIR="${ORDERER_STATE_DIR}/tls"

echo "=============================================="
echo " Orderer Enrollment"
echo "=============================================="
echo

echo "CA       : ${CA_URL}"
echo "Orderer  : ${ORDERER_NAME}"
echo "Orderer IP : ${ORDERER_IP}"
echo

# ============================================================
# Prepare state
# ============================================================

rm -rf "${ORDERER_STATE_DIR}"

mkdir -p \
    "${ORDERER_STATE_DIR}" \
    "${ORDERER_MSP_DIR}" \
    "${ORDERER_TLS_DIR}"

# ============================================================
# Wait for CA
# ============================================================

echo "----------------------------------------------"
echo " Waiting for Fabric CA"
echo "----------------------------------------------"
echo

for i in $(seq 1 60); do
    if fabric-ca-client getcainfo \
        -u "${CA_URL}" \
        --caname ca \
        >/dev/null 2>&1
    then
        echo "Fabric CA is ready."
        break
    fi

    if [ "${i}" -eq 60 ]; then
        echo "ERROR: Fabric CA did not become available."
        exit 1
    fi

    echo "Waiting for Fabric CA... (${i}/60)"
    sleep 1
done

echo

# ============================================================
# CA administrator
# ============================================================

export FABRIC_CA_CLIENT_HOME="${ORDERER_STATE_DIR}/admin"

mkdir -p "${FABRIC_CA_CLIENT_HOME}"

echo "----------------------------------------------"
echo " Enrolling CA administrator"
echo "----------------------------------------------"
echo

fabric-ca-client enroll \
    -u "http://admin:adminpw@${CA_NAME}:${CA_PORT}" \
    --caname ca

echo "CA administrator enrolled."
echo

# ============================================================
# Register orderer identity
# ============================================================

echo "----------------------------------------------"
echo " Registering orderer"
echo "----------------------------------------------"
echo

fabric-ca-client register \
    --caname ca \
    --id.name "${ORDERER_IDENTITY}" \
    --id.secret "${ORDERER_PASSWORD}" \
    --id.type orderer \
    --id.affiliation "org1.orderer" \
    -u "${CA_URL}"

echo "Orderer registered."
echo

# ============================================================
# Enroll orderer MSP
# ============================================================

echo "----------------------------------------------"
echo " Enrolling orderer MSP"
echo "----------------------------------------------"
echo

export FABRIC_CA_CLIENT_HOME="${ORDERER_MSP_DIR}"

fabric-ca-client enroll \
    --caname ca \
    -u "http://${ORDERER_IDENTITY}:${ORDERER_PASSWORD}@${CA_NAME}:${CA_PORT}" \
    -M "${ORDERER_MSP_DIR}"

echo "Orderer MSP generated."
echo

# ============================================================
# Register TLS identity
# ============================================================

export FABRIC_CA_CLIENT_HOME="${ORDERER_STATE_DIR}/admin"

echo "----------------------------------------------"
echo " Registering orderer TLS identity"
echo "----------------------------------------------"
echo

fabric-ca-client register \
    --caname ca \
    --id.name "${ORDERER_TLS_IDENTITY}" \
    --id.secret "${ORDERER_TLS_PASSWORD}" \
    --id.type orderer \
    --id.affiliation "org1.orderer" \
    -u "${CA_URL}"

echo "Orderer TLS identity registered."
echo

# ============================================================
# Enroll TLS
# ============================================================

echo "----------------------------------------------"
echo " Enrolling orderer TLS"
echo "----------------------------------------------"
echo

export FABRIC_CA_CLIENT_HOME="${ORDERER_TLS_DIR}"

fabric-ca-client enroll \
    --caname ca \
    -u "http://${ORDERER_TLS_IDENTITY}:${ORDERER_TLS_PASSWORD}@${CA_NAME}:${CA_PORT}" \
    -M "${ORDERER_TLS_DIR}" \
    --enrollment.profile tls \
    --csr.hosts "${ORDERER_NAME},${ORDERER_IP},localhost"

echo "Orderer TLS material generated."
echo

# ============================================================
# Normalize TLS files
# ============================================================

TLS_CERT="$(find "${ORDERER_TLS_DIR}/signcerts" -type f -print -quit)"
TLS_KEY="$(find "${ORDERER_TLS_DIR}/keystore" -type f -print -quit)"
TLS_CA="$(find "${ORDERER_TLS_DIR}/tlscacerts" -type f -print -quit)"

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

cp "${TLS_CERT}" "${ORDERER_TLS_DIR}/server.crt"
cp "${TLS_KEY}" "${ORDERER_TLS_DIR}/server.key"
cp "${TLS_CA}" "${ORDERER_TLS_DIR}/ca.crt"

echo "TLS files normalized."
echo

# ============================================================
# MSP configuration
# ============================================================

cat > "${ORDERER_MSP_DIR}/config.yaml" <<'EOF'
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

mkdir -p "${ORDERER_MSP_DIR}/tlscacerts"

cp \
    "${ORDERER_TLS_DIR}/ca.crt" \
    "${ORDERER_MSP_DIR}/tlscacerts/ca.crt"

# ============================================================
# Validation
# ============================================================

echo "----------------------------------------------"
echo " Validating orderer material"
echo "----------------------------------------------"
echo

test -f "${ORDERER_MSP_DIR}/signcerts/cert.pem"

find "${ORDERER_MSP_DIR}/keystore" \
    -type f \
    -print \
    -quit | grep -q .

test -f "${ORDERER_MSP_DIR}/config.yaml"
test -f "${ORDERER_TLS_DIR}/server.crt"
test -f "${ORDERER_TLS_DIR}/server.key"
test -f "${ORDERER_TLS_DIR}/ca.crt"

echo "Orderer MSP ........ OK"
echo "Orderer TLS ........ OK"

echo
echo "=============================================="
echo " Orderer Enrollment Complete"
echo "=============================================="
echo
echo "State:"
echo "  ${ORDERER_STATE_DIR}"
echo
echo "The orderer has NOT been started."
echo "Docker Compose will start it after bootstrap exits."
echo