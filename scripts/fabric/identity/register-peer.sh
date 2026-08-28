#!/bin/bash

set -e

PEER_NAME="${1:?Usage: $0 <peer-name>}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADMIN_MSP="$PROJECT_ROOT/vnf-manager/identities/org-admin/msp"

if [ ! -d "$ADMIN_MSP" ]; then
    echo "Error: organization admin MSP not found:"
    echo "  $ADMIN_MSP"
    exit 1
fi

echo "=============================================="
echo " Registering Fabric peer"
echo "=============================================="
echo
echo "Peer: ${PEER_NAME}"
echo

docker run --rm \
    --network XIT \
    -v "$ADMIN_MSP:/admin-msp:ro" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client register \
    --url http://fabric-ca:7054 \
    --id.name "$PEER_NAME" \
    --id.secret "${PEER_NAME}pw" \
    --id.type peer \
    --mspdir /admin-msp

echo
echo "=============================================="
echo " Peer ${PEER_NAME} registered successfully"
echo "=============================================="