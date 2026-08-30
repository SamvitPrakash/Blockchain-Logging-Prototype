#!/bin/sh

set -eu

# ============================================================
# FABRIC-ENROLL nested Fabric peer enrollment
# ============================================================

: "${VNF_INSTANCE:?VNF_INSTANCE is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

PEER_NAME="${PEER_NAME:-fabric-peer-${VNF_INSTANCE}}"
PEER_SECRET="${PEER_SECRET:-peerpw}"
CA_IP="${CA_IP:-10.10.0.11}"
PEER_IP="${PEER_IP:-10.10.0.$((100 + VNF_INSTANCE))}"
PEER_HOSTNAME="${PEER_HOSTNAME:-${PEER_NAME}}"

PEER_STATE_DIR="${PEER_STATE_DIR:-${VNF_STATE_DIR}/peer}"

CA_ADMIN="${CA_ADMIN:-admin}"
CA_ADMIN_SECRET="${CA_ADMIN_SECRET:-adminpw}"

CA_URL="http://${CA_IP}:7054"

CLIENT_HOME="${PEER_STATE_DIR}/client"
MSP_DIR="${PEER_STATE_DIR}/msp"
TLS_DIR="${PEER_STATE_DIR}/tls"
ADMIN_MSP_DIR="${PEER_STATE_DIR}/admin-msp"

echo "=============================================="
echo " Enrolling Fabric peer"
echo "=============================================="
echo
echo "Peer       : ${PEER_NAME}"
echo "Hostname   : ${PEER_HOSTNAME}"
echo "IP         : ${PEER_IP}"
echo "CA         : ${CA_URL}"
echo "State      : ${PEER_STATE_DIR}"
echo

mkdir -p "${PEER_STATE_DIR}"

rm -rf \
    "${CLIENT_HOME}" \
    "${MSP_DIR}" \
    "${TLS_DIR}" \
    "${ADMIN_MSP_DIR}"

mkdir -p \
    "${CLIENT_HOME}" \
    "${MSP_DIR}" \
    "${TLS_DIR}" \
    "${ADMIN_MSP_DIR}"

# ------------------------------------------------------------
# Enroll peer MSP
# ------------------------------------------------------------

echo "Enrolling peer MSP..."

fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_SECRET}@${CA_IP}:7054" \
    --home "${CLIENT_HOME}" \
    -M "${MSP_DIR}" \
    --csr.cn "${PEER_HOSTNAME}"

# ------------------------------------------------------------
# Enroll peer TLS
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
# Fabric TLS layout
# ------------------------------------------------------------

TLS_CERT="$(find "${TLS_DIR}/signcerts" -type f -name '*.pem' -print -quit)"
TLS_KEY="$(find "${TLS_DIR}/keystore" -type f -name '*_sk' -print -quit)"
TLS_CA="$(find "${TLS_DIR}/tlscacerts" -type f -name '*.pem' -print -quit)"

[ -n "${TLS_CERT}" ] || {
    echo "Error: TLS certificate was not generated."
    exit 1
}

[ -n "${TLS_KEY}" ] || {
    echo "Error: TLS private key was not generated."
    exit 1
}

[ -n "${TLS_CA}" ] || {
    echo "Error: TLS CA certificate was not generated."
    exit 1
}

cp "${TLS_CERT}" "${TLS_DIR}/server.crt"
cp "${TLS_KEY}"  "${TLS_DIR}/server.key"
cp "${TLS_CA}"  "${TLS_DIR}/ca.crt"

# ------------------------------------------------------------
# MSP Node OU configuration
# ------------------------------------------------------------

CA_CERT="$(find "${MSP_DIR}/cacerts" -type f -name '*.pem' -print -quit)"

[ -n "${CA_CERT}" ] || {
    echo "Error: MSP CA certificate was not generated."
    exit 1
}

cat > "${MSP_DIR}/config.yaml" <<EOF
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    Certificate: cacerts/$(basename "${CA_CERT}")
    OrganizationalUnitIdentifier: client

  PeerOUIdentifier:
    Certificate: cacerts/$(basename "${CA_CERT}")
    OrganizationalUnitIdentifier: peer

  AdminOUIdentifier:
    Certificate: cacerts/$(basename "${CA_CERT}")
    OrganizationalUnitIdentifier: admin

  OrdererOUIdentifier:
    Certificate: cacerts/$(basename "${CA_CERT}")
    OrganizationalUnitIdentifier: orderer
EOF

# ------------------------------------------------------------
# Enroll Org1 admin MSP
#
# This identity is NOT used by the peer daemon.
# It exists for administrative Fabric CLI operations such as:
#
#   peer channel join
#   peer channel list
#
# The CA bootstrap admin is enrolled into a separate MSP.
# ------------------------------------------------------------

echo "Enrolling Org1 admin MSP..."

ADMIN_CLIENT_HOME="${CLIENT_HOME}/org1-admin"

rm -rf "${ADMIN_CLIENT_HOME}"

mkdir -p "${ADMIN_CLIENT_HOME}"

fabric-ca-client enroll \
    -u "http://${CA_ADMIN}:${CA_ADMIN_SECRET}@${CA_IP}:7054" \
    --home "${ADMIN_CLIENT_HOME}" \
    -M "${ADMIN_MSP_DIR}" \
    --csr.cn "org1-admin"

ADMIN_CA_CERT="$(find "${ADMIN_MSP_DIR}/cacerts" -type f -name '*.pem' -print -quit)"

[ -n "${ADMIN_CA_CERT}" ] || {
    echo "Error: Org1 admin CA certificate was not generated."
    exit 1
}

cat > "${ADMIN_MSP_DIR}/config.yaml" <<EOF
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    Certificate: cacerts/$(basename "${ADMIN_CA_CERT}")
    OrganizationalUnitIdentifier: client

  PeerOUIdentifier:
    Certificate: cacerts/$(basename "${ADMIN_CA_CERT}")
    OrganizationalUnitIdentifier: peer

  AdminOUIdentifier:
    Certificate: cacerts/$(basename "${ADMIN_CA_CERT}")
    OrganizationalUnitIdentifier: admin

  OrdererOUIdentifier:
    Certificate: cacerts/$(basename "${ADMIN_CA_CERT}")
    OrganizationalUnitIdentifier: orderer
EOF

# ------------------------------------------------------------
# Ownership
# ------------------------------------------------------------

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

chown -R \
    "${HOST_UID}:${HOST_GID}" \
    "${PEER_STATE_DIR}"

echo
echo "=============================================="
echo " Peer identities generated"
echo "=============================================="
echo
echo "Peer MSP:"
echo "  ${MSP_DIR}"
echo
echo "Peer TLS:"
echo "  ${TLS_DIR}"
echo
echo "Org1 Admin MSP:"
echo "  ${ADMIN_MSP_DIR}"
echo
echo "=============================================="
echo " Enrollment complete"
echo "=============================================="