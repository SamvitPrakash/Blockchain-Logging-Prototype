#!/bin/bash

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADMIN_NAME="org-admin"
ADMIN_SECRET="org-adminpw"

OUTPUT_DIR="$PROJECT_ROOT/vnf-manager/identities/${ADMIN_NAME}"
CA_ADMIN_DIR="$PROJECT_ROOT/vnf-manager/identities/ca-admin"

echo "=============================================="
echo " Registering Fabric organization admin"
echo "=============================================="
echo

mkdir -p "$CA_ADMIN_DIR"
mkdir -p "$OUTPUT_DIR"

echo "1. Enrolling Fabric CA bootstrap admin..."
echo

docker run --rm \
    --network XIT \
    -v "$CA_ADMIN_DIR:/ca-admin" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client enroll \
    -u "http://admin:adminpw@fabric-ca:7054" \
    --mspdir /ca-admin/msp

echo
echo "2. Registering organization admin..."
echo

docker run --rm \
    --network XIT \
    -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client register \
    --url http://fabric-ca:7054 \
    --id.name "$ADMIN_NAME" \
    --id.secret "$ADMIN_SECRET" \
    --id.type admin \
    --mspdir /admin-msp

echo
echo "3. Enrolling organization admin..."
echo

docker run --rm \
    --network XIT \
    -v "$OUTPUT_DIR:/output" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client enroll \
    -u "http://${ADMIN_NAME}:${ADMIN_SECRET}@fabric-ca:7054" \
    --mspdir /output/msp

sudo chown -R "$(id -u):$(id -g)" "$OUTPUT_DIR"

echo
echo "=============================================="
echo " Organization admin created successfully"
echo "=============================================="
echo
echo "Admin MSP:"
echo "  $OUTPUT_DIR/msp"
echo