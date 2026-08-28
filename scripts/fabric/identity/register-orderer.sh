#!/bin/bash

set -e

ORDERER_NAME="${1:?Usage: $0 <orderer-name>}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADMIN_MSP="$PROJECT_ROOT/vnf-manager/identities/org-admin/msp"

if [ ! -d "$ADMIN_MSP" ]; then
    echo "Error: organization admin MSP not found:"
    echo "  $ADMIN_MSP"
    exit 1
fi

echo "=============================================="
echo " Registering Fabric orderer"
echo "=============================================="
echo
echo "Orderer: ${ORDERER_NAME}"
echo

docker run --rm \
    --network XIT \
    -v "$ADMIN_MSP:/admin-msp:ro" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client register \
    --url http://fabric-ca:7054 \
    --id.name "$ORDERER_NAME" \
    --id.secret "${ORDERER_NAME}pw" \
    --id.type orderer \
    --mspdir /admin-msp

echo
echo "=============================================="
echo " Orderer ${ORDERER_NAME} registered successfully"
echo "=============================================="