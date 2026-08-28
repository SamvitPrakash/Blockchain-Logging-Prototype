#!/bin/bash

set -e

PEER_NAME="${1:?Usage: $0 <peer-name>}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

OUTPUT_DIR="$PROJECT_ROOT/vnf-manager/identities/${PEER_NAME}"

mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo " Enrolling Fabric peer TLS identity"
echo "=============================================="
echo
echo "Peer: ${PEER_NAME}"
echo

docker run --rm \
    --network XIT \
    -v "$OUTPUT_DIR:/output" \
    hyperledger/fabric-ca:1.5.17 \
    fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_NAME}pw@fabric-ca:7054" \
    --enrollment.profile tls \
    --csr.hosts "${PEER_NAME}" \
    --mspdir /output/tls

sudo chown -R "$(id -u):$(id -g)" "$OUTPUT_DIR"

echo
echo "=============================================="
echo " TLS enrollment complete"
echo "=============================================="
echo
echo "TLS material:"
echo "  $OUTPUT_DIR/tls"