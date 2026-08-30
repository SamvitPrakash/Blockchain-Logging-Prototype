#!/bin/sh

set -eu

# ============================================================
# FABRIC-ENROLL nested Fabric peer registration
# ============================================================

: "${VNF_INSTANCE:?VNF_INSTANCE is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

PEER_NAME="${PEER_NAME:-fabric-peer-${VNF_INSTANCE}}"
PEER_SECRET="${PEER_SECRET:-peerpw}"
PEER_IP="${PEER_IP:-10.10.0.$((100 + VNF_INSTANCE))}"
PEER_HOSTNAME="${PEER_HOSTNAME:-${PEER_NAME}}"
PEER_STATE_DIR="${PEER_STATE_DIR:-${VNF_STATE_DIR}/peer}"

CA_IP="${CA_IP:-10.10.0.11}"
CA_URL="http://${CA_IP}:7054"

CA_ADMIN="${CA_ADMIN:-admin}"
CA_ADMIN_SECRET="${CA_ADMIN_SECRET:-adminpw}"

ADMIN_NAME="${ADMIN_NAME:-org1-admin}"
ADMIN_SECRET="${ADMIN_SECRET:-org1adminpw}"

CLIENT_HOME="${PEER_STATE_DIR}/client"
CA_ADMIN_HOME="${CLIENT_HOME}/ca-admin"

echo "=============================================="
echo " Registering Fabric peer identities"
echo "=============================================="
echo
echo "Peer:"
echo "  Name       : ${PEER_NAME}"
echo "  Hostname   : ${PEER_HOSTNAME}"
echo "  IP         : ${PEER_IP}"
echo
echo "Org admin:"
echo "  Name       : ${ADMIN_NAME}"
echo
echo "CA:"
echo "  ${CA_URL}"
echo
echo "State:"
echo "  ${PEER_STATE_DIR}"
echo

mkdir -p "${PEER_STATE_DIR}" "${CLIENT_HOME}"

# ------------------------------------------------------------
# Enroll CA bootstrap administrator
# ------------------------------------------------------------

echo "Enrolling CA bootstrap administrator..."

rm -rf "${CA_ADMIN_HOME}"

fabric-ca-client enroll \
    -u "http://${CA_ADMIN}:${CA_ADMIN_SECRET}@${CA_IP}:7054" \
    --home "${CA_ADMIN_HOME}"

export FABRIC_CA_CLIENT_HOME="${CA_ADMIN_HOME}"

# ------------------------------------------------------------
# Register peer identity
#
# Registration is intentionally idempotent. The CA database is
# persistent, so rebuilding/restarting a FABRIC-ENROLL instance
# must not fail merely because the identity already exists.
# ------------------------------------------------------------

echo
echo "Registering peer identity..."

if fabric-ca-client register \
    --id.name "${PEER_NAME}" \
    --id.secret "${PEER_SECRET}" \
    --id.affiliation "org1" \
    --id.type peer \
    -u "${CA_URL}"
then
    echo "Peer identity registered: ${PEER_NAME}"
else
    echo "Peer identity already exists or registration failed."

    # Re-run registration only for diagnostics. A registration
    # failure is tolerated only when Fabric CA explicitly reports
    # that the identity already exists.
    REGISTER_OUTPUT="$(
        fabric-ca-client register \
            --id.name "${PEER_NAME}" \
            --id.secret "${PEER_SECRET}" \
            --id.affiliation "org1" \
            --id.type peer \
            -u "${CA_URL}" \
            2>&1 || true
    )"

    if printf '%s\n' "${REGISTER_OUTPUT}" | grep -qi "already registered"; then
        echo "Peer identity already registered: ${PEER_NAME}"
    else
        echo "${REGISTER_OUTPUT}"
        echo
        echo "ERROR: peer identity registration failed."
        exit 1
    fi
fi

# ------------------------------------------------------------
# Register organization admin identity
#
# This identity is used by Fabric CLI operations such as:
#
#   peer channel join
#   peer channel list
#
# The admin identity must have Fabric CA type "admin" so that
# NodeOUs places OU=admin in its enrollment certificate.
# ------------------------------------------------------------

echo
echo "Registering organization admin identity..."

if fabric-ca-client register \
    --id.name "${ADMIN_NAME}" \
    --id.secret "${ADMIN_SECRET}" \
    --id.affiliation "org1" \
    --id.type admin \
    -u "${CA_URL}"
then
    echo "Organization admin identity registered: ${ADMIN_NAME}"
else
    REGISTER_OUTPUT="$(
        fabric-ca-client register \
            --id.name "${ADMIN_NAME}" \
            --id.secret "${ADMIN_SECRET}" \
            --id.affiliation "org1" \
            --id.type admin \
            -u "${CA_URL}" \
            2>&1 || true
    )"

    if printf '%s\n' "${REGISTER_OUTPUT}" | grep -qi "already registered"; then
        echo "Organization admin identity already registered: ${ADMIN_NAME}"
    else
        echo "${REGISTER_OUTPUT}"
        echo
        echo "ERROR: organization admin registration failed."
        exit 1
    fi
fi

echo
echo "=============================================="
echo " Fabric identities registered"
echo "=============================================="
echo
echo "Peer:"
echo "  ${PEER_NAME}"
echo
echo "Admin:"
echo "  ${ADMIN_NAME}"
echo
echo "Next:"
echo
echo "  enroll-peer.sh"
echo