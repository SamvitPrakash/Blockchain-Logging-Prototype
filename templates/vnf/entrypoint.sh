#!/bin/bash

set -euo pipefail

: "${VNF_ID:?VNF_ID is required}"
: "${GNB_ID:?GNB_ID is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

CA_IP="${FABRIC_CA_IP:-10.10.0.11}"
CA_PORT="${FABRIC_CA_PORT:-7054}"

echo "=============================================="
echo " VNF starting"
echo "=============================================="
echo
echo "VNF ID       : ${VNF_ID}"
echo "gNB ID       : ${GNB_ID}"
echo "Fabric Peer  : ${FABRIC_PEER}"
echo "Fabric CA    : ${CA_IP}:${CA_PORT}"
echo

mkdir -p "${VNF_STATE_DIR}"

echo "Waiting for Fabric CA at ${CA_IP}:${CA_PORT}..."

until (echo >"/dev/tcp/${CA_IP}/${CA_PORT}") >/dev/null 2>&1; do
    echo "  Fabric CA not ready, retrying..."
    sleep 2
done

echo "Fabric CA is reachable."
echo

if [ -d "${VNF_STATE_DIR}/msp" ] \
    && [ -d "${VNF_STATE_DIR}/msp/signcerts" ] \
    && [ -d "${VNF_STATE_DIR}/msp/keystore" ]; then

    echo "Existing VNF identity found."
    echo "Skipping registration and enrollment."

else

    echo "=============================================="
    echo " Provisioning VNF identity"
    echo "=============================================="
    echo

    /opt/vnf/register-vnf.sh
    /opt/vnf/enroll-vnf.sh

fi

echo
echo "=============================================="
echo " Starting VNF application"
echo "=============================================="
echo

exec python -m src.main