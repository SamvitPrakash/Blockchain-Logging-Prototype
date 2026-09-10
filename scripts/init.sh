#!/bin/bash

MARKER="scripts/.init"

if [ -f "$MARKER" ]; then
    exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$PROJECT_ROOT/templates"
BOOTSTRAP_DIR="$TEMPLATE_DIR"/fabric-bootstrap
CA_DIR="$TEMPLATE_DIR"/fabric-ca
ENROLL_DIR="$TEMPLATE_DIR"/fabric-enroll
VNF_DIR="$TEMPLATE_DIR"/vnf
VNFM_DIR="$TEMPLATE_DIR"/vnfm

echo
echo "################################################"
echo "Running initialization..."
echo "################################################"


echo
echo "================================================"
echo "Building FABRIC-BOOTSTRAP"
echo "================================================"

for file in \
    Dockerfile \
    entrypoint.sh \
    enroll-orderer.sh
do
    if [ ! -f "$BOOTSTRAP_DIR/$file" ]; then
        echo "Error: FABRIC-BOOTSTRAP template file not found:"
        echo "  $BOOTSTRAP_DIR/$file"
        exit 1
    fi
done

BOOTSTRAP_IMAGE="blockchain-fabric-bootstrap:latest"

docker build \
    -t "$BOOTSTRAP_IMAGE" \
    "$BOOTSTRAP_DIR"

echo
echo "================================================"
echo "Building FABRIC-CA"
echo "================================================"

for file in \
    Dockerfile \
    ca-server-config.yaml
do
    if [ ! -f "$CA_DIR/$file" ]; then
        echo "Error: FABRIC-CA template file not found:"
        echo "  $CA_DIR/$file"
        exit 1
    fi
done

CA_IMAGE="blockchain-fabric-ca:latest"

docker build \
    -t "$CA_IMAGE" \
    "$CA_DIR"

echo
echo "================================================"
echo "Building FABRIC-ENROLL"
echo "================================================"

for file in \
    Dockerfile \
    entrypoint.sh \
    register-peer.sh \
    enroll-peer.sh \
    prepare-peer.sh
do
    if [ ! -f "$ENROLL_DIR/$file" ]; then
        echo "Error: FABRIC-ENROLL template file not found:"
        echo "  $ENROLL_DIR/$file"
        exit 1
    fi
done

ENROLL_IMAGE="blockchain-fabric-enroll:latest"

docker build \
    -t "$ENROLL_IMAGE" \
    "$ENROLL_DIR"

echo
echo "================================================"
echo "Building VNF"
echo "================================================"

for file in \
    Dockerfile \
    entrypoint.sh \
    register-vnf.sh \
    enroll-vnf.sh \
    package.json \
    src/main.js
do
    if [ ! -f "$VNF_DIR/$file" ]; then
        echo "Error: VNF template file missing:"
        echo "  $VNF_DIR/$file"
        exit 1
    fi
done

VNF_IMAGE="blockchain-logging-vnf:latest"

docker build \
    -t "$VNF_IMAGE" \
    "$VNF_DIR"

echo
echo "================================================"
echo "Building VNFM"
echo "================================================"

for file in \
    Dockerfile \
    entrypoint.sh \
    join-orderer.sh \
    manage-chaincode.sh \
    provision-identity.sh
do
    if [ ! -f "$VNFM_DIR/$file" ]; then
        echo "Error: VNFM template missing:"
        echo "  $VNFM_DIR/$file"
        exit 1
    fi
done

VNFM_IMAGE="blockchain-vnfm:latest"

docker build \
    -t "$VNFM_IMAGE" \
    "$VNFM_DIR"

echo
echo "================================================"
echo "Building Ueransim"
echo "================================================"

./scripts/open5gs/BuildUeramsim.sh

echo
echo "================================================"
echo "Building Open5GS Core"
echo "================================================"

./scripts/open5gs/BuildCore.sh

echo
echo "================================================"
echo "Running Open5GS Core initialization"
echo "================================================"

./scripts/open5gs/Core.sh

echo
echo "########################################################################"
echo "Initialization complete."
echo "########################################################################"

touch "$MARKER"

exit 0