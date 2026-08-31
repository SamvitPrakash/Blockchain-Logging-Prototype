#!/bin/bash

set -euo pipefail

: "${VNF_ID:?VNF_ID is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

CA_IP="${FABRIC_CA_IP:-10.10.0.11}"
CA_PORT="${FABRIC_CA_PORT:-7054}"

VNF_SECRET="${VNF_SECRET:-vnfpw}"

VNF_CLIENT_HOME="${VNF_STATE_DIR}/client"
VNF_MSP_DIR="${VNF_STATE_DIR}/msp"

echo "=============================================="
echo " Enrolling VNF"
echo "=============================================="
echo
echo "VNF        : ${VNF_ID}"
echo "CA         : http://${CA_IP}:${CA_PORT}"
echo "MSP        : ${VNF_MSP_DIR}"
echo

mkdir -p "${VNF_CLIENT_HOME}"

rm -rf "${VNF_MSP_DIR}"

mkdir -p "${VNF_MSP_DIR}"

echo "Enrolling VNF MSP..."

fabric-ca-client enroll \
    -u "http://${VNF_ID}:${VNF_SECRET}@${CA_IP}:${CA_PORT}" \
    --home "${VNF_CLIENT_HOME}" \
    -M "${VNF_MSP_DIR}" \
    --csr.cn "${VNF_ID}"

CA_CERT="$(find "${VNF_MSP_DIR}/cacerts" -type f -name '*.pem' -print -quit)"

if [ -z "${CA_CERT}" ]; then
    echo "Error: VNF MSP CA certificate was not generated."
    exit 1
fi

cat > "${VNF_MSP_DIR}/config.yaml" <<EOF
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

echo
echo "=============================================="
echo " VNF enrollment complete"
echo "=============================================="
echo
echo "VNF MSP:"
echo "  ${VNF_MSP_DIR}"
echo