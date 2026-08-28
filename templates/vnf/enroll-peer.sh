#!/bin/bash

set -e

: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_SECRET:?PEER_SECRET is required}"
: "${CA_IP:?CA_IP is required}"
: "${PEER_IP:?PEER_IP is required}"
: "${PEER_HOSTNAME:?PEER_HOSTNAME is required}"
: "${PEER_STATE_DIR:?PEER_STATE_DIR is required}"

CA_URL="http://${CA_IP}:7054"

CLIENT_HOME="${PEER_STATE_DIR}/client"
MSP_DIR="${PEER_STATE_DIR}/msp"
TLS_DIR="${PEER_STATE_DIR}/tls"

echo "=============================================="
echo " Enrolling Fabric peer"
echo "=============================================="
echo
echo "Peer       : ${PEER_NAME}"
echo "Hostname   : ${PEER_HOSTNAME}"
echo "IP         : ${PEER_IP}"
echo "CA         : ${CA_URL}"
echo

rm -rf "${CLIENT_HOME}"
rm -rf "${MSP_DIR}"
rm -rf "${TLS_DIR}"

mkdir -p \
    "${CLIENT_HOME}" \
    "${MSP_DIR}" \
    "${TLS_DIR}"

# ------------------------------------------------------------
# Enroll peer MSP identity
# ------------------------------------------------------------

echo "Enrolling peer MSP..."

fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_SECRET}@${CA_IP}:7054" \
    --home "${CLIENT_HOME}" \
    -M "${MSP_DIR}" \
    --csr.cn "${PEER_HOSTNAME}"

# ------------------------------------------------------------
# Enroll peer TLS identity
# ------------------------------------------------------------

echo "Enrolling peer TLS identity..."

fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_SECRET}@${CA_IP}:7054" \
    --home "${CLIENT_HOME}" \
    --enrollment.profile tls \
    -M "${TLS_DIR}" \
    --csr.cn "${PEER_HOSTNAME}" \
    --csr.hosts "${PEER_HOSTNAME},${PEER_IP}"

# ------------------------------------------------------------
# Convert TLS enrollment into Fabric peer TLS layout
# ------------------------------------------------------------

TLS_CERT="$(find "${TLS_DIR}/signcerts" -type f -name '*.pem' -print -quit)"
TLS_KEY="$(find "${TLS_DIR}/keystore" -type f -name '*_sk' -print -quit)"
TLS_CA="$(find "${TLS_DIR}/tlscacerts" -type f -name '*.pem' -print -quit)"

if [ -z "${TLS_CERT}" ]; then
    echo "Error: TLS certificate was not generated."
    exit 1
fi

if [ -z "${TLS_KEY}" ]; then
    echo "Error: TLS private key was not generated."
    exit 1
fi

if [ -z "${TLS_CA}" ]; then
    echo "Error: TLS CA certificate was not generated."
    exit 1
fi

cp "${TLS_CERT}" "${TLS_DIR}/server.crt"
cp "${TLS_KEY}"  "${TLS_DIR}/server.key"
cp "${TLS_CA}"   "${TLS_DIR}/ca.crt"

# ------------------------------------------------------------
# MSP Node OU configuration
# ------------------------------------------------------------

cat > "${MSP_DIR}/config.yaml" <<'MSPCONFIG'
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: client

  PeerOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: peer

  AdminOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: admin

  OrdererOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: orderer
MSPCONFIG

# ------------------------------------------------------------
# Locate CA certificate
# ------------------------------------------------------------

CA_CERT="$(find "${MSP_DIR}/cacerts" -type f -name '*.pem' -print -quit)"

if [ -z "${CA_CERT}" ]; then
    echo "Error: CA certificate was not generated."
    exit 1
fi

echo
echo "=============================================="
echo " Peer identity generated"
echo "=============================================="
echo
echo "MSP:"
find "${MSP_DIR}" -type f -print | sort
echo
echo "TLS:"
find "${TLS_DIR}" -type f -print | sort
echo
