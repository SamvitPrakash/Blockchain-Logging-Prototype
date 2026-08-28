#!/bin/bash

set -euo pipefail

# ============================================================
# Fabric prototype setup
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IDENTITY_DIR="$PROJECT_ROOT/vnf-manager/identities"
FABRIC_NETWORK="XIT"
FABRIC_CA_CONTAINER="fabric-ca"
FABRIC_CA_IMAGE="hyperledger/fabric-ca:1.5.17"
PEER_TEMPLATE="$PROJECT_ROOT/templates/fabric/peer-compose.yaml"
PEER_COMPOSE="$PROJECT_ROOT/vnf/peer/compose.yaml"
PEERS=(
    "peer0"
)

IDENTITY_ROOT="$PROJECT_ROOT/vnf-manager/identities"

echo "=============================================="
echo " Hyperledger Fabric Prototype Setup"
echo "=============================================="
echo
echo "Project root:     $PROJECT_ROOT"
echo "Fabric network:   $FABRIC_NETWORK"
echo "CA container:     $FABRIC_CA_CONTAINER"
echo "Identity storage: $IDENTITY_ROOT"
echo

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running or the current user cannot access it."
    exit 1
fi

# ------------------------------------------------------------
# Docker network
# ------------------------------------------------------------

if ! docker network inspect "$FABRIC_NETWORK" >/dev/null 2>&1; then
    echo "Creating Docker network: $FABRIC_NETWORK"
    docker network create "$FABRIC_NETWORK"
else
    echo "Docker network already exists: $FABRIC_NETWORK"
fi

# ------------------------------------------------------------
# Fabric CA
# ------------------------------------------------------------

echo
echo "Starting Fabric CA..."
echo

if docker container inspect "$FABRIC_CA_CONTAINER" >/dev/null 2>&1; then
    if [ "$(docker inspect -f '{{.State.Running}}' "$FABRIC_CA_CONTAINER")" = "true" ]; then
        echo "Fabric CA is already running."
    else
        echo "Starting existing Fabric CA container..."
        docker start "$FABRIC_CA_CONTAINER" >/dev/null
    fi
else
    echo "Creating Fabric CA container..."

    docker compose \
        -f "$PROJECT_ROOT/vnf-manager/ca/compose.yaml" \
        up -d
fi

echo
echo "Waiting for Fabric CA..."

for i in {1..30}; do
    if docker exec "$FABRIC_CA_CONTAINER" \
        fabric-ca-client version >/dev/null 2>&1; then
        echo "Fabric CA is ready."
        break
    fi

    if [ "$i" -eq 30 ]; then
        echo "Error: Fabric CA did not become ready."
        docker logs "$FABRIC_CA_CONTAINER" --tail 50
        exit 1
    fi

    sleep 1
done

echo
echo "Fabric CA is running."

# ------------------------------------------------------------
# CA bootstrap administrator
# ------------------------------------------------------------

CA_ADMIN_DIR="$IDENTITY_ROOT/ca-admin"
ORG_ADMIN_DIR="$IDENTITY_ROOT/org-admin"
ORDERER_DIR="$IDENTITY_ROOT/orderer0"
ORDERER_COMPOSE="$PROJECT_ROOT/vnf-manager/orderer/compose.yaml"
ORDERER_TEMPLATE="$PROJECT_ROOT/templates/fabric/orderer-compose.yaml"
GENESIS_DIR="$PROJECT_ROOT/vnf-manager/orderer/genesis"
GENESIS_BLOCK="$GENESIS_DIR/genesis.block"

echo
echo "Setting up Fabric CA administrator..."
echo

mkdir -p "$CA_ADMIN_DIR"

if [ ! -f "$CA_ADMIN_DIR/msp/signcerts/cert.pem" ]; then
    echo "Enrolling CA bootstrap administrator..."

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$CA_ADMIN_DIR:/ca-admin" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client enroll \
        -u "http://admin:adminpw@${FABRIC_CA_CONTAINER}:7054" \
        --mspdir /ca-admin/msp

    sudo chown -R "$(id -u):$(id -g)" "$CA_ADMIN_DIR"

    echo "CA bootstrap administrator enrolled."
else
    echo "CA bootstrap administrator already enrolled."
fi

# ------------------------------------------------------------
# Organization administrator
# ------------------------------------------------------------

echo
echo "Setting up organization administrator..."
echo

mkdir -p "$ORG_ADMIN_DIR"

if [ ! -f "$ORG_ADMIN_DIR/msp/signcerts/cert.pem" ]; then

    echo "Registering organization administrator..."

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client register \
        --url "http://${FABRIC_CA_CONTAINER}:7054" \
        --id.name "org-admin" \
        --id.secret "org-adminpw" \
        --id.type admin \
        --mspdir /admin-msp

    echo "Enrolling organization administrator..."

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$ORG_ADMIN_DIR:/output" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client enroll \
        -u "http://org-admin:org-adminpw@${FABRIC_CA_CONTAINER}:7054" \
        --mspdir /output/msp

    sudo chown -R "$(id -u):$(id -g)" "$ORG_ADMIN_DIR"

    echo "Organization administrator enrolled."

    cp "$PROJECT_ROOT/templates/fabric/identities-config.yaml" \
    "$IDENTITY_DIR/org-admin/msp/config.yaml"

    echo "Organization MSP configuration installed."
else
    echo "Organization administrator already enrolled."
fi

echo
echo "CA administrator:"
echo "  $CA_ADMIN_DIR/msp"

echo
echo "Organization administrator:"
echo "  $ORG_ADMIN_DIR/msp"

# ------------------------------------------------------------
# Peer registration and enrollment
# ------------------------------------------------------------

echo
echo "Setting up Fabric peers..."
echo

for PEER_NAME in "${PEERS[@]}"; do

    PEER_DIR="$IDENTITY_ROOT/$PEER_NAME"

    echo "----------------------------------------------"
    echo " Peer: $PEER_NAME"
    echo "----------------------------------------------"

    mkdir -p "$PEER_DIR"

    # --------------------------------------------------------
    # Register peer if it does not already exist
    # --------------------------------------------------------

    if ! docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client identity list \
        --id "$PEER_NAME" \
        --url "http://${FABRIC_CA_CONTAINER}:7054" \
        --mspdir /admin-msp 2>/dev/null | grep -q "Name: $PEER_NAME,"; then

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

    else
        echo "$PEER_NAME is already registered."
    fi

    # --------------------------------------------------------
    # Peer MSP enrollment
    # --------------------------------------------------------

    if [ ! -f "$PEER_DIR/msp/signcerts/cert.pem" ]; then

        echo "Enrolling $PEER_NAME MSP..."

        TEMP_DIR="$(mktemp -d)"

        docker run --rm \
            --network "$FABRIC_NETWORK" \
            -v "$TEMP_DIR:/output" \
            "$FABRIC_CA_IMAGE" \
            fabric-ca-client enroll \
            -u "http://${PEER_NAME}:${PEER_NAME}pw@${FABRIC_CA_CONTAINER}:7054" \
            --mspdir /output/msp

        sudo cp -a "$TEMP_DIR/msp" "$PEER_DIR/"
        sudo rm -rf "$TEMP_DIR"
        sudo chown -R "$(id -u):$(id -g)" "$PEER_DIR"

    else
        echo "$PEER_NAME MSP already exists."
    fi

    # --------------------------------------------------------
    # Peer MSP administrator certificate
    # --------------------------------------------------------

    mkdir -p "$PEER_DIR/msp/admincerts"

    cp \
        "$ORG_ADMIN_DIR/msp/signcerts/cert.pem" \
        "$PEER_DIR/msp/admincerts/org-admin-cert.pem"

    echo "Configured organization administrator for $PEER_NAME MSP."

    # --------------------------------------------------------
    # Peer TLS enrollment
    # --------------------------------------------------------

    if [ ! -f "$PEER_DIR/tls/signcerts/cert.pem" ]; then

        echo "Enrolling $PEER_NAME TLS..."

        TEMP_DIR="$(mktemp -d)"

        docker run --rm \
            --network "$FABRIC_NETWORK" \
            -v "$TEMP_DIR:/output" \
            "$FABRIC_CA_IMAGE" \
            fabric-ca-client enroll \
            -u "http://${PEER_NAME}:${PEER_NAME}pw@${FABRIC_CA_CONTAINER}:7054" \
            --enrollment.profile tls \
            --csr.hosts "$PEER_NAME" \
            --mspdir /output/tls

        sudo cp -a "$TEMP_DIR/tls" "$PEER_DIR/"
        sudo rm -rf "$TEMP_DIR"
        sudo chown -R "$(id -u):$(id -g)" "$PEER_DIR"

    else
        echo "$PEER_NAME TLS already exists."
    fi

    sudo chown -R "$(id -u):$(id -g)" "$PEER_DIR"

    # --------------------------------------------------------
    # Find TLS private key
    # --------------------------------------------------------

    mapfile -t TLS_KEYS < <(
        find "$PEER_DIR/tls/keystore" \
            -maxdepth 1 \
            -type f \
            -name '*_sk'
    )

    if [ "${#TLS_KEYS[@]}" -ne 1 ]; then
        echo "Error: expected exactly one TLS private key for $PEER_NAME."
        echo "Found ${#TLS_KEYS[@]} keys:"

        if [ "${#TLS_KEYS[@]}" -gt 0 ]; then
            printf '  %s\n' "${TLS_KEYS[@]}"
        fi

        exit 1
    fi

    TLS_KEY="$(basename "${TLS_KEYS[0]}")"

    echo "TLS private key: $TLS_KEY"

    # --------------------------------------------------------
    # Generate peer Compose configuration
    # --------------------------------------------------------

    mkdir -p "$PROJECT_ROOT/vnf/peer"

    sed \
        -e "s|\${PEER_NAME}|$PEER_NAME|g" \
        -e "s|\${TLS_KEY}|$TLS_KEY|g" \
        -e "s|\${IDENTITY_DIR}|$PEER_DIR|g" \
        -e "s|\${FABRIC_NETWORK}|$FABRIC_NETWORK|g" \
        -e "s|\${PEER_PORT}|7051|g" \
        -e "s|\${CHAINCODE_PORT}|7052|g" \
        "$PEER_TEMPLATE" > "$PEER_COMPOSE"

    echo "Generated:"
    echo "  $PEER_COMPOSE"

    echo
    echo "$PEER_NAME identity ready."
    echo

done

# ------------------------------------------------------------
# Orderer registration and enrollment
# ------------------------------------------------------------

echo
echo "Setting up Fabric orderer..."
echo

mkdir -p "$ORDERER_DIR"

# --------------------------------------------------------
# Register orderer
# --------------------------------------------------------

if ! docker run --rm \
    --network "$FABRIC_NETWORK" \
    -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
    "$FABRIC_CA_IMAGE" \
    fabric-ca-client identity list \
    --id orderer0 \
    --url "http://${FABRIC_CA_CONTAINER}:7054" \
    --mspdir /admin-msp 2>/dev/null | grep -q "Name: orderer0,"; then

    echo "Registering orderer0..."

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$CA_ADMIN_DIR/msp:/admin-msp:ro" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client register \
        --url "http://${FABRIC_CA_CONTAINER}:7054" \
        --id.name "orderer0" \
        --id.secret "orderer0pw" \
        --id.type orderer \
        --mspdir /admin-msp

else
    echo "orderer0 is already registered."
fi

# --------------------------------------------------------
# Orderer MSP
# --------------------------------------------------------

if [ ! -f "$ORDERER_DIR/msp/signcerts/cert.pem" ]; then

    echo "Enrolling orderer0 MSP..."

    TEMP_DIR="$(mktemp -d)"

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$TEMP_DIR:/output" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client enroll \
        -u "http://orderer0:orderer0pw@${FABRIC_CA_CONTAINER}:7054" \
        --mspdir /output/msp

    sudo cp -a "$TEMP_DIR/msp" "$ORDERER_DIR/"
    sudo rm -rf "$TEMP_DIR"
    sudo chown -R "$(id -u):$(id -g)" "$ORDERER_DIR"

else
    echo "orderer0 MSP already exists."
fi

# --------------------------------------------------------
# Orderer MSP administrator certificate
# --------------------------------------------------------

mkdir -p "$ORDERER_DIR/msp/admincerts"

cp \
    "$ORG_ADMIN_DIR/msp/signcerts/cert.pem" \
    "$ORDERER_DIR/msp/admincerts/org-admin-cert.pem"

echo "Configured organization administrator for orderer0 MSP."

# --------------------------------------------------------
# Orderer TLS
# --------------------------------------------------------

if [ ! -f "$ORDERER_DIR/tls/signcerts/cert.pem" ]; then

    echo "Enrolling orderer0 TLS..."

    TEMP_DIR="$(mktemp -d)"

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$TEMP_DIR:/output" \
        "$FABRIC_CA_IMAGE" \
        fabric-ca-client enroll \
        -u "http://orderer0:orderer0pw@${FABRIC_CA_CONTAINER}:7054" \
        --enrollment.profile tls \
        --csr.hosts "orderer0" \
        --mspdir /output/tls

    sudo cp -a "$TEMP_DIR/tls" "$ORDERER_DIR/"
    sudo rm -rf "$TEMP_DIR"
    sudo chown -R "$(id -u):$(id -g)" "$ORDERER_DIR"

else
    echo "orderer0 TLS already exists."
fi

sudo chown -R "$(id -u):$(id -g)" "$ORDERER_DIR"

# --------------------------------------------------------
# Find orderer TLS private key
# --------------------------------------------------------

mapfile -t ORDERER_TLS_KEYS < <(
    find "$ORDERER_DIR/tls/keystore" \
        -maxdepth 1 \
        -type f \
        -name '*_sk'
)

if [ "${#ORDERER_TLS_KEYS[@]}" -ne 1 ]; then
    echo "Error: expected exactly one TLS private key for orderer0."
    echo "Found ${#ORDERER_TLS_KEYS[@]} keys:"
    printf '  %s\n' "${ORDERER_TLS_KEYS[@]}"
    exit 1
fi

ORDERER_TLS_KEY="$(basename "${ORDERER_TLS_KEYS[0]}")"

echo "Orderer TLS private key: $ORDERER_TLS_KEY"

# ------------------------------------------------------------
# Generate orderer Compose configuration
# ------------------------------------------------------------

mkdir -p "$PROJECT_ROOT/vnf-manager/orderer"

sed \
    -e "s|\${ORDERER_TLS_KEY}|$ORDERER_TLS_KEY|g" \
    -e "s|\${IDENTITY_DIR}|$ORDERER_DIR|g" \
    -e "s|\${FABRIC_NETWORK}|$FABRIC_NETWORK|g" \
    -e "s|\${GENESIS_BLOCK}|$GENESIS_BLOCK|g" \
    "$ORDERER_TEMPLATE" > "$ORDERER_COMPOSE"

echo "Generated:"
echo "  $ORDERER_COMPOSE"

# ------------------------------------------------------------
# Generate genesis block
# ------------------------------------------------------------

echo
echo "Generating Fabric genesis block..."
echo

mkdir -p "$GENESIS_DIR"

if [ ! -f "$GENESIS_BLOCK" ]; then

    docker run --rm \
        --network "$FABRIC_NETWORK" \
        -v "$PROJECT_ROOT/vnf-manager:/workspace" \
        -v "$PROJECT_ROOT/fabric-samples:/fabric-samples" \
        -w /workspace \
        hyperledger/fabric-tools:2.5 \
        configtxgen \
        -profile XITGenesis \
        -channelID system-channel \
        -configPath /workspace/config \
        -outputBlock /workspace/orderer/genesis/genesis.block

    sudo chown "$(id -u):$(id -g)" "$GENESIS_BLOCK"

    echo "Genesis block generated:"
    echo "  $GENESIS_BLOCK"

else
    echo "Genesis block already exists."
fi

echo
echo "=============================================="
echo " Starting Fabric orderer"
echo "=============================================="
echo

if [ ! -f "$ORDERER_COMPOSE" ]; then
    echo "Error: orderer compose file was not generated:"
    echo "  $ORDERER_COMPOSE"
    exit 1
fi

docker compose -f "$ORDERER_COMPOSE" up -d

echo
echo "Waiting for orderer to start..."
sleep 3

docker compose -f "$ORDERER_COMPOSE" ps

echo
echo "=============================================="
echo " Starting Fabric peers"
echo "=============================================="
echo

if [ ! -f "$PEER_COMPOSE" ]; then
    echo "Error: peer compose file was not generated:"
    echo "  $PEER_COMPOSE"
    exit 1
fi

docker compose -f "$PEER_COMPOSE" up -d

echo
echo "Waiting for peers to start..."
sleep 3

docker compose -f "$PEER_COMPOSE" ps