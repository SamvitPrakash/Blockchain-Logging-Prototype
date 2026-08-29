#!/bin/sh

set -eu

# ============================================================
# FABRIC-ENROLL nested Fabric peer registration
# ============================================================

: "${VNF_INSTANCE:?VNF_INSTANCE is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

PEER_NAME="${PEER_NAME:-fabric-peer-${VNF_INSTANCE}}"
PEER_SECRET="${PEER_SECRET:-peerpw}"
CA_IP="${CA_IP:-10.10.0.11}"
PEER_IP="${PEER_IP:-10.10.0.$((100 + VNF_INSTANCE))}"
PEER_HOSTNAME="${PEER_HOSTNAME:-${PEER_NAME}}"
PEER_STATE_DIR="${PEER_STATE_DIR:-${VNF_STATE_DIR}/peer}"

CA_URL="http://${CA_IP}:7054"
CLIENT_HOME="${PEER_STATE_DIR}/client"

echo "=============================================="
echo " Registering Fabric peer"
echo "=============================================="
echo
echo "Peer       : ${PEER_NAME}"
echo "Hostname   : ${PEER_HOSTNAME}"
echo "IP         : ${PEER_IP}"
echo "CA         : ${CA_URL}"
echo "State      : ${PEER_STATE_DIR}"
echo

mkdir -p "${PEER_STATE_DIR}" "${CLIENT_HOME}"

# ------------------------------------------------------------
# Enroll CA administrator
#
# The CA server is initialized with the admin identity.
# These credentials must match the CA server configuration.
# ------------------------------------------------------------

CA_ADMIN="${CA_ADMIN:-admin}"
CA_ADMIN_SECRET="${CA_ADMIN_SECRET:-adminpw}"

echo "Enrolling CA administrator..."

rm -rf "${CLIENT_HOME}/ca-admin"

fabric-ca-client enroll \
    -u "http://${CA_ADMIN}:${CA_ADMIN_SECRET}@${CA_IP}:7054" \
    --home "${CLIENT_HOME}/ca-admin"

# ------------------------------------------------------------
# Register peer identity
# ------------------------------------------------------------

echo "Registering peer..."

export FABRIC_CA_CLIENT_HOME="${CLIENT_HOME}/ca-admin"

fabric-ca-client register \
    --id.name "${PEER_NAME}" \
    --id.secret "${PEER_SECRET}" \
    --id.affiliation "org1" \
    --id.type peer \
    -u "${CA_URL}"

echo
echo "=============================================="
echo " Peer registered successfully"
echo "=============================================="
echo
echo "Peer:"
echo "  Name       : ${PEER_NAME}"
echo "  Secret     : ${PEER_SECRET}"
echo "  Affiliation: org1"
echo
echo "Next:"
echo
echo "  ./build/fabric-enroll-${VNF_INSTANCE}/enroll-peer.sh"
echo