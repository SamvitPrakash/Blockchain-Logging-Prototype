#!/bin/bash

set -euo pipefail

# ============================================================
# VNFM Generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

TEMPLATE_DIR="$PROJECT_ROOT/templates/vnfm"

BUILD_DIR="$PROJECT_ROOT/build/vnfm"

FABRIC_NETWORK_BUILD_DIR="$PROJECT_ROOT/build/fabric-network"

TOPOLOGY_SOURCE="$FABRIC_NETWORK_BUILD_DIR/topology.json"
CHANNEL_SOURCE="$FABRIC_NETWORK_BUILD_DIR/channels"

VNFM_NAME="vnfm"
VNFM_IMAGE="blockchain-vnfm:latest"

ORDERER_NAME="fabric-orderer-1"
ORDERER_IP="10.10.0.20"

VNFM_IP="10.10.0.30"

XIT_NETWORK="XIT"

# ============================================================
# VNFM container paths
# ============================================================

VNFM_STATE_DIR="/opt/vnfm-state"
VNFM_CREDENTIAL_DIR="/opt/vnfm-credentials"

VNFM_TOPOLOGY_FILE="${VNFM_STATE_DIR}/topology.json"
VNFM_CHANNEL_BLOCK_DIR="${VNFM_STATE_DIR}/channels"

VNFM_TLS_CA="${VNFM_CREDENTIAL_DIR}/ca.crt"
VNFM_TLS_CLIENT_CERT="${VNFM_CREDENTIAL_DIR}/client.crt"
VNFM_TLS_CLIENT_KEY="${VNFM_CREDENTIAL_DIR}/client.key"

# ============================================================
# VNFM host paths
# ============================================================

VNFM_CREDENTIAL_HOST_DIR="${BUILD_DIR}/credentials"

# ============================================================
# Fabric CA
# ============================================================

CA_NAME="fabric-ca"
CA_ENDPOINT="${CA_NAME}:7054"

VNFM_CA_IDENTITY="vnfm"
VNFM_CA_PASSWORD="vnfmpw"

# ============================================================
# Fabric CA client image
# ============================================================

FABRIC_CA_CLIENT_IMAGE="hyperledger/fabric-ca:1.5.15"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TOPOLOGY_SOURCE" ]; then
    echo "Error: Fabric network topology does not exist:"
    echo "  $TOPOLOGY_SOURCE"
    echo
    echo "Generate the Fabric network first."
    exit 1
fi

if [ ! -d "$CHANNEL_SOURCE" ]; then
    echo "Error: Fabric network channel directory does not exist:"
    echo "  $CHANNEL_SOURCE"
    exit 1
fi

for file in \
    Dockerfile \
    entrypoint.sh \
    join-orderer.sh \
    provision-identity.sh
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: VNFM template file not found:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network '${XIT_NETWORK}' does not exist."
    echo
    echo "Run:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

if docker inspect "$VNFM_NAME" >/dev/null 2>&1; then
    echo "Error: container '${VNFM_NAME}' already exists."
    exit 1
fi

if docker inspect "$CA_NAME" >/dev/null 2>&1; then
    CA_STATUS="$(docker inspect -f '{{.State.Status}}' "$CA_NAME")"

    if [ "$CA_STATUS" != "running" ]; then
        echo "Error: Fabric CA container exists but is not running."
        echo
        echo "Start Fabric CA first:"
        echo
        echo "  docker start ${CA_NAME}"
        exit 1
    fi
else
    echo "Error: Fabric CA container '${CA_NAME}' does not exist."
    echo
    echo "Generate and start Fabric CA first."
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    echo
    echo "Remove it before regenerating:"
    echo
    echo "  rm -rf ${BUILD_DIR}"
    echo
    exit 1
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p \
    "$BUILD_DIR" \
    "$VNFM_CREDENTIAL_HOST_DIR"

# ============================================================
# Copy topology
# ============================================================

cp "$TOPOLOGY_SOURCE" \
   "$BUILD_DIR/topology.json"

# ============================================================
# Copy channel blocks
# ============================================================

cp -a "$CHANNEL_SOURCE" \
      "$BUILD_DIR/channels"

# ============================================================
# Provision VNFM identity
# ============================================================

echo
echo "=============================================="
echo " Provisioning VNFM identity"
echo "=============================================="
echo

echo "CA:"
echo "  ${CA_NAME}"

echo
echo "VNFM identity:"
echo "  ${VNFM_CA_IDENTITY}"

echo
echo "Output:"
echo "  ${VNFM_CREDENTIAL_HOST_DIR}"

echo
echo "CA client image:"
echo "  ${FABRIC_CA_CLIENT_IMAGE}"

"$TEMPLATE_DIR/provision-identity.sh" \
    "$VNFM_CREDENTIAL_HOST_DIR" \
    "$CA_ENDPOINT" \
    "$VNFM_CA_IDENTITY" \
    "$VNFM_CA_PASSWORD" \
    "$FABRIC_CA_CLIENT_IMAGE"

echo
echo "VNFM credentials:"
echo "  ${VNFM_CREDENTIAL_HOST_DIR}"
echo

# ============================================================
# Verify credentials
# ============================================================

for file in \
    ca.crt \
    client.crt \
    client.key
do
    if [ ! -f "$VNFM_CREDENTIAL_HOST_DIR/$file" ]; then
        echo "Error: VNFM credential was not generated:"
        echo "  $VNFM_CREDENTIAL_HOST_DIR/$file"
        exit 1
    fi
done

# ============================================================
# Build VNFM image
# ============================================================

echo "Building VNFM image:"
echo "  ${VNFM_IMAGE}"
echo

docker build \
    -t "$VNFM_IMAGE" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  vnfm:
    image: ${VNFM_IMAGE}

    container_name: ${VNFM_NAME}
    hostname: ${VNFM_NAME}

    environment:

      VNFM_NAME: "${VNFM_NAME}"

      VNFM_ORDERER_NAME: "${ORDERER_NAME}"
      VNFM_ORDERER_ADMIN_ENDPOINT: "${ORDERER_NAME}:9443"

      VNFM_TOPOLOGY_FILE: "${VNFM_TOPOLOGY_FILE}"
      VNFM_CHANNEL_BLOCK_DIR: "${VNFM_CHANNEL_BLOCK_DIR}"

      VNFM_TLS_CA: "${VNFM_TLS_CA}"
      VNFM_TLS_CLIENT_CERT: "${VNFM_TLS_CLIENT_CERT}"
      VNFM_TLS_CLIENT_KEY: "${VNFM_TLS_CLIENT_KEY}"

      VNFM_WAIT_INTERVAL: "2"
      VNFM_WAIT_TIMEOUT: "120"

    volumes:

      - ${BUILD_DIR}:${VNFM_STATE_DIR}:ro
      - ${VNFM_CREDENTIAL_HOST_DIR}:${VNFM_CREDENTIAL_DIR}:ro

    networks:

      xit:
        ipv4_address: ${VNFM_IP}

    restart: unless-stopped

networks:

  xit:
    external: true
    name: ${XIT_NETWORK}
EOF

# ============================================================
# Validate Compose
# ============================================================

echo
echo "Validating generated Compose file..."

docker compose \
    -f "$BUILD_DIR/compose.yaml" \
    config >/dev/null

echo "Compose configuration is valid."

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNFM generated"
echo "=============================================="
echo

echo "VNFM:"
echo "  Name:       ${VNFM_NAME}"
echo "  IP:         ${VNFM_IP}"
echo

echo "Orderer:"
echo "  Name:       ${ORDERER_NAME}"
echo "  IP:         ${ORDERER_IP}"
echo "  Admin:      ${ORDERER_NAME}:9443"
echo

echo "Topology:"
echo "  ${BUILD_DIR}/topology.json"
echo

echo "Channels:"
echo "  ${BUILD_DIR}/channels/"
echo

echo "Credentials:"
echo "  ${VNFM_CREDENTIAL_HOST_DIR}/"
echo

echo "Compose:"
echo "  ${BUILD_DIR}/compose.yaml"
echo