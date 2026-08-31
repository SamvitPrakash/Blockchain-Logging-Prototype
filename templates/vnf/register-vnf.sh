#!/bin/bash

set -euo pipefail

: "${VNF_ID:?VNF_ID is required}"
: "${VNF_STATE_DIR:?VNF_STATE_DIR is required}"

CA_IP="${FABRIC_CA_IP:-10.10.0.11}"
CA_PORT="${FABRIC_CA_PORT:-7054}"

CA_ADMIN="${CA_ADMIN:-admin}"
CA_ADMIN_SECRET="${CA_ADMIN_SECRET:-adminpw}"

VNF_SECRET="${VNF_SECRET:-vnfpw}"

CA_URL="http://${CA_IP}:${CA_PORT}"

CLIENT_HOME="${VNF_STATE_DIR}/client"
CA_ADMIN_HOME="${CLIENT_HOME}/ca-admin"

echo "=============================================="
echo " Registering VNF"
echo "=============================================="
echo
echo "VNF        : ${VNF_ID}"
echo "CA         : ${CA_URL}"
echo "State      : ${VNF_STATE_DIR}"
echo

mkdir -p "${CA_ADMIN_HOME}"

echo "Enrolling CA administrator..."

fabric-ca-client enroll \
    -u "http://${CA_ADMIN}:${CA_ADMIN_SECRET}@${CA_IP}:${CA_PORT}" \
    --home "${CA_ADMIN_HOME}"

echo
echo "Registering VNF identity..."

export FABRIC_CA_CLIENT_HOME="${CA_ADMIN_HOME}"

fabric-ca-client register \
    --id.name "${VNF_ID}" \
    --id.secret "${VNF_SECRET}" \
    --id.affiliation "org1" \
    --id.type client \
    -u "${CA_URL}"

echo
echo "=============================================="
echo " VNF registered successfully"
echo "=============================================="
echo
echo "VNF:"
echo "  ID         : ${VNF_ID}"
echo "  Type       : client"
echo "  Affiliation: org1"
echo