#!/bin/bash

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FABRIC_NETWORK="XIT"
IDENTITY_DIR="$PROJECT_ROOT/vnf-manager/identities"
CA_DATA_DIR="$PROJECT_ROOT/vnf-manager/ca/data"
PEER_COMPOSE="$PROJECT_ROOT/vnf/peer/compose.yaml"
ORDERER_COMPOSE="$PROJECT_ROOT/vnf-manager/orderer/compose.yaml"
GENESIS_DIR="$PROJECT_ROOT/vnf-manager/orderer/genesis"
GENESIS_BLOCK="$GENESIS_DIR/genesis.block"

echo "=============================================="
echo " Hyperledger Fabric Prototype Teardown"
echo "=============================================="
echo
echo "Project root:     $PROJECT_ROOT"
echo "Fabric network:   $FABRIC_NETWORK"
echo "Identity storage: $IDENTITY_DIR"
echo

# ------------------------------------------------
# 1. Stop Fabric peers
# ------------------------------------------------

echo "1. Stopping Fabric peers..."
echo

if [ -f "$PEER_COMPOSE" ]; then
    docker compose \
        -f "$PEER_COMPOSE" \
        down \
        --remove-orphans
else
    echo "Peer compose file not found. Skipping."
fi

echo

# ------------------------------------------------
# 2. Stop Fabric orderer
# ------------------------------------------------

echo "2. Stopping Fabric orderer..."
echo

if [ -f "$ORDERER_COMPOSE" ]; then
    docker compose \
        -f "$ORDERER_COMPOSE" \
        down \
        --remove-orphans
else
    echo "Orderer compose file not found. Skipping."
fi

echo

# ------------------------------------------------
# 3. Remove Fabric CA
# ------------------------------------------------

echo "3. Removing Fabric CA..."
echo

if docker container inspect fabric-ca >/dev/null 2>&1; then
    docker rm -f fabric-ca >/dev/null
    echo "Fabric CA container removed."
else
    echo "Fabric CA container does not exist."
fi

echo

# ------------------------------------------------
# 4. Remove Fabric CA data
# ------------------------------------------------

echo "4. Removing Fabric CA data..."
echo

if [ -d "$CA_DATA_DIR" ]; then
    sudo rm -rf "$CA_DATA_DIR"
    echo "Removed:"
    echo "  $CA_DATA_DIR"
else
    echo "Fabric CA data directory does not exist."
fi

echo

# ------------------------------------------------
# 5. Remove generated identities
# ------------------------------------------------

echo "5. Removing generated identities..."

if [ -d "$IDENTITY_DIR" ]; then
    rm -rf "$IDENTITY_DIR"
    echo "Removed:"
    echo "  $IDENTITY_DIR"
else
    echo "Identity directory does not exist."
fi

echo

# ------------------------------------------------
# 6. Remove generated genesis block
# ------------------------------------------------

echo "6. Removing generated genesis block..."
echo

if [ -f "$GENESIS_BLOCK" ]; then
    rm -f "$GENESIS_BLOCK"
    echo "Removed:"
    echo "  $GENESIS_BLOCK"
else
    echo "Genesis block does not exist."
fi

echo

# ------------------------------------------------
# 7. Remove generated peer configuration
# ------------------------------------------------

echo "7. Removing generated peer configuration..."

if [ -f "$PEER_COMPOSE" ]; then
    rm -f "$PEER_COMPOSE"
    echo "Removed:"
    echo "  $PEER_COMPOSE"
else
    echo "Peer compose file does not exist."
fi

echo

# ------------------------------------------------
# 8. Remove Fabric network
# ------------------------------------------------

echo "8. Removing Fabric Docker network..."

if docker network inspect "$FABRIC_NETWORK" >/dev/null 2>&1; then

    if docker network rm "$FABRIC_NETWORK" >/dev/null; then
        echo "Network removed:"
        echo "  $FABRIC_NETWORK"
    else
        echo "ERROR: Network still has active endpoints."
        echo
        docker network inspect "$FABRIC_NETWORK" \
            --format '{{range .Containers}}  {{.Name}} ({{.IPv4Address}}){{"\n"}}{{end}}'
        exit 1
    fi

else
    echo "Network does not exist."
fi

echo
echo "=============================================="
echo " Fabric teardown complete"
echo "=============================================="