#!/bin/bash

set -e

# ============================================================
# VNFM Generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

TEMPLATE_DIR="$PROJECT_ROOT/templates/vnfm"

BUILD_DIR="$PROJECT_ROOT/build/vnfm"

FABRIC_NETWORK_BUILD_DIR="$PROJECT_ROOT/build/fabric-network"
FABRIC_BOOTSTRAP_BUILD_DIR="$PROJECT_ROOT/build/fabric-bootstrap"

TOPOLOGY_SOURCE="$FABRIC_NETWORK_BUILD_DIR/topology.json"
CHANNEL_SOURCE="$FABRIC_NETWORK_BUILD_DIR/channels"

VNFM_NAME="vnfm"

ORDERER_NAME="fabric-orderer-1"
ORDERER_IP="10.10.0.20"

VNFM_IP="10.10.0.30"

XIT_NETWORK="XIT"

VNFM_STATE_DIR="/opt/vnfm-state"

VNFM_TOPOLOGY_FILE="${VNFM_STATE_DIR}/topology.json"
VNFM_CHANNEL_BLOCK_DIR="${VNFM_STATE_DIR}/channels"

VNFM_CREDENTIAL_DIR="${VNFM_STATE_DIR}/credentials"

VNFM_TLS_CA="${VNFM_CREDENTIAL_DIR}/ca.crt"
VNFM_TLS_CLIENT_CERT="${VNFM_CREDENTIAL_DIR}/client.crt"
VNFM_TLS_CLIENT_KEY="${VNFM_CREDENTIAL_DIR}/client.key"

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
    join-orderer.sh
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: VNFM template file not found:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo
    echo "Run:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

if docker inspect "$VNFM_NAME" >/dev/null 2>&1; then
    echo "Error: container '${VNFM_NAME}' already exists."
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
# Create build directory
# ============================================================

mkdir -p "$BUILD_DIR"

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
# Build VNFM image
# ============================================================

IMAGE_NAME="blockchain-vnfm:latest"

echo
echo "Building VNFM image:"
echo "  ${IMAGE_NAME}"
echo

docker build \
    -t "$IMAGE_NAME" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  vnfm:
    image: ${IMAGE_NAME}

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
echo "Compose:"
echo "  ${BUILD_DIR}/compose.yaml"

echo
echo "=============================================="