#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FABRIC_NETWORK="XIT"
FABRIC_CA_CONTAINER="fabric-ca"
FABRIC_CA_IMAGE="hyperledger/fabric-ca:1.5.17"

IDENTITY_ROOT="$PROJECT_ROOT/vnf-manager/identities"
CA_ADMIN_DIR="$IDENTITY_ROOT/ca-admin"

PEER_NAME="peer-vnf-${INSTANCE}"
PEER_IDENTITY_DIR="$IDENTITY_ROOT/peers/$PEER_NAME"

echo "=============================================="
echo " Creating Fabric peer identity"
echo "=============================================="
echo
echo "Peer:       $PEER_NAME"
echo "Identity:   $PEER_IDENTITY_DIR"
echo

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running or unavailable."
    exit 1
fi

# ------------------------------------------------------------
# Check XIT
# ------------------------------------------------------------

if ! docker network inspect "$FABRIC_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    exit 1
fi

# ------------------------------------------------------------
# Check CA
# ------------------------------------------------------------

if ! docker container inspect "$FABRIC_CA_CONTAINER" >/dev/null 2>&1; then
    echo "Error: Fabric CA container does not exist."
    exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$FABRIC_CA_CONTAINER")" != "true" ]; then
    echo "Error: Fabric CA is not running."
    exit 1
fi

# ------------------------------------------------------------
# Create CA administrator identity
# ------------------------------------------------------------

mkdir -p "$CA_ADMIN_DIR"

if [ ! -f "$CA_ADMIN_DIR/msp/signcerts/cert.pem" ]; then

    echo "Enrolling CA administrator..."

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$CA_ADMIN_DIR:/output" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client enroll \
        -u "http://admin:adminpw@${FABRIC_CA_CONTAINER}:7054" \
        --mspdir /output/msp

    sudo chown -R "$(id -u):$(id -g)" "$CA_ADMIN_DIR"

    echo "CA administrator enrolled."

else

    echo "CA administrator already exists."

fi

# ------------------------------------------------------------
# Prevent duplicate peer identity
# ------------------------------------------------------------

if [ -d "$PEER_IDENTITY_DIR" ]; then
    echo
    echo "Error: identity already exists:"
    echo "  $PEER_IDENTITY_DIR"
    exit 1
fi

mkdir -p "$PEER_IDENTITY_DIR"

# ------------------------------------------------------------
# Register peer
# ------------------------------------------------------------

echo
echo "Registering $PEER_NAME..."

docker run --rm \
    --network "$FABRIC_NETWORK" \
    -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
    "$FABRIC_CA_IMAGE" \
    fabric-ca-client register \
    --url "http://${FABRIC_CA_CONTAINER}:7054" \
    --id.name "$PEER_NAME" \
    --id.secret "${PEER_NAME}pw" \
    --id.type peer \
    --mspdir /admin-msp

# ------------------------------------------------------------
# Enroll peer MSP
# ------------------------------------------------------------

echo
echo "Enrolling $PEER_NAME MSP..."

docker run --rm \
    --network "$FABRIC_NETWORK" \
    -v "$PEER_IDENTITY_DIR:/output" \
    "$FABRIC_CA_IMAGE" \
    fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_NAME}pw@${FABRIC_CA_CONTAINER}:7054" \
    --mspdir /output/msp

# ------------------------------------------------------------
# Enroll peer TLS identity
# ------------------------------------------------------------

echo
echo "Enrolling $PEER_NAME TLS identity..."

docker run --rm \
    --network "$FABRIC_NETWORK" \
    -v "$PEER_IDENTITY_DIR:/output" \
    "$FABRIC_CA_IMAGE" \
    fabric-ca-client enroll \
    -u "http://${PEER_NAME}:${PEER_NAME}pw@${FABRIC_CA_CONTAINER}:7054" \
    --enrollment.profile tls \
    --mspdir /output/tls

# ------------------------------------------------------------
# Fix generated identity ownership
# ------------------------------------------------------------

sudo chown -R "$(id -u):$(id -g)" "$PEER_IDENTITY_DIR"

# ------------------------------------------------------------
# Install MSP config
# ------------------------------------------------------------

cp "$PROJECT_ROOT/templates/fabric/identities-config.yaml" \
   "$PEER_IDENTITY_DIR/msp/config.yaml"
   
echo
echo "=============================================="
echo " Peer identity created successfully"
echo "=============================================="
echo
echo "Peer:"
echo "  $PEER_NAME"
echo
echo "Identity:"
echo "  $PEER_IDENTITY_DIR"
echo