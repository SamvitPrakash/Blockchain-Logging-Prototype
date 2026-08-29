#!/bin/bash

set -euo pipefail

echo "=============================================="
echo " Starting VNF"
echo "=============================================="

echo
echo "VNF instance : ${VNF_INSTANCE}"
echo "VNF name     : ${VNF_NAME}"
echo "OAM network  : ${OAM_NETWORK}"
echo "OAM address  : ${OAM_IP}"
echo "XIT network  : ${XIT_NETWORK}"
echo "Peer address : ${PEER_IP}"
echo

: "${VNF_INSTANCE:?VNF_INSTANCE is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"
: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_HOSTNAME:?PEER_HOSTNAME is required}"
: "${PEER_IP:?PEER_IP is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"
: "${HOST_PEER_STATE_DIR:?HOST_PEER_STATE_DIR is required}"

CA_IP="${CA_IP:-10.10.0.11}"
CA_PORT="${CA_PORT:-7054}"

echo "Waiting for Fabric CA at ${CA_IP}:${CA_PORT}..."

until (echo >"/dev/tcp/${CA_IP}/${CA_PORT}") >/dev/null 2>&1; do
    echo "  Fabric CA not ready, retrying..."
    sleep 2
done

echo "Fabric CA is reachable."
echo

echo "=============================================="
echo " Registering peer"
echo "=============================================="

/opt/vnf/register-peer.sh

echo
echo "=============================================="
echo " Enrolling peer"
echo "=============================================="

/opt/vnf/enroll-peer.sh

echo
echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="

/opt/vnf/start-peer.sh

echo
echo "=============================================="
echo " VNF ready"
echo "=============================================="
echo

exec sleep infinity