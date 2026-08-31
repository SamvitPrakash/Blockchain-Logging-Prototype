#!/bin/bash

set -e

echo "=============================================="
echo " VNF starting"
echo "=============================================="
echo

: "${VNF_ID:?VNF_ID is required}"
: "${GNB_ID:?GNB_ID is required}"
: "${FABRIC_PEER:?FABRIC_PEER is required}"
: "${FABRIC_PEER_IP:?FABRIC_PEER_IP is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

FABRIC_CA_IP="${FABRIC_CA_IP:-10.10.0.11}"
FABRIC_CA_PORT="${FABRIC_CA_PORT:-7054}"

echo "VNF ID       : ${VNF_ID}"
echo "gNB ID       : ${GNB_ID}"
echo "Fabric Peer  : ${FABRIC_PEER}"
echo "Fabric CA    : ${FABRIC_CA_IP}:${FABRIC_CA_PORT}"
echo

echo "Waiting for Fabric CA at ${FABRIC_CA_IP}:${FABRIC_CA_PORT}..."

until bash -c "echo > /dev/tcp/${FABRIC_CA_IP}/${FABRIC_CA_PORT}" \
    >/dev/null 2>&1
do
    sleep 2
done

echo "Fabric CA is reachable."
echo

# ============================================================
# Provision VNF identity
# ============================================================

if [ ! -f "${VNF_STATE_DIR}/msp/signcerts/cert.pem" ]; then

    echo "=============================================="
    echo " Provisioning VNF identity"
    echo "=============================================="
    echo

    /opt/vnf/register-vnf.sh
    /opt/vnf/enroll-vnf.sh

else

    echo "=============================================="
    echo " VNF identity already exists"
    echo "=============================================="
    echo

    echo "Using existing MSP:"
    echo "  ${VNF_STATE_DIR}/msp"
    echo
fi

# ============================================================
# Start application
# ============================================================

echo
echo "=============================================="
echo " Starting VNF application"
echo "=============================================="
echo

exec node /opt/vnf/src/main.js