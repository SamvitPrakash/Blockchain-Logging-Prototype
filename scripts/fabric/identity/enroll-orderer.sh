#!/bin/bash

set -e

ORDERER_NAME="${1:?Usage: $0 <orderer-name>}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

OUTPUT_DIR="$PROJECT_ROOT/vnf-manager/identities/${ORDERER_NAME}"

mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo " Enrolling Fabric orderer TLS identity"
echo "=============================================="
echo
echo "Orderer: ${ORDERER_NAME}"
echo

docker run --rm \
    --network XIT \
    -v "$OUTPUT_DIR:/output" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client enroll \
    -u "http://${ORDERER_NAME}:${ORDERER_NAME}pw@fabric-ca:7054" \
    --enrollment.profile tls \
    --csr.hosts "${ORDERER_NAME}" \
    --csr.hosts localhost \
    --mspdir /output/tls

sudo chown -R "$(id -u):$(id -g)" "$OUTPUT_DIR"

echo
echo "=============================================="
echo " TLS enrollment complete"
echo "=============================================="
echo
echo "TLS material:"
echo "  $OUTPUT_DIR/tls"