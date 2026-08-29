#!/bin/bash

set -e

# ============================================================
# VNFM Generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

TEMPLATE_DIR="$PROJECT_ROOT/templates/vnfm"
BUILD_DIR="$PROJECT_ROOT/build/vnfm"

VNFM_NAME="vnfm"

# ------------------------------------------------------------
# Network addressing
# ------------------------------------------------------------

VNFM_IP="10.10.0.10"
CA_IP="10.10.0.11"
ORDERER_IP="10.10.0.20"

XIT_NETWORK="XIT"

# ------------------------------------------------------------
# Host/container paths
# ------------------------------------------------------------

CA_HOST_DATA_DIR="$BUILD_DIR/ca"
ORDERER_HOST_DATA_DIR="$BUILD_DIR/orderer"

VNFM_STATE_DIR="/opt/vnfm-state"

# ------------------------------------------------------------
# Host ownership
# ------------------------------------------------------------

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# ============================================================
# Validation
# ============================================================

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "Error: project root does not exist:"
    echo "  $PROJECT_ROOT"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/Dockerfile" ]; then
    echo "Error: VNFM Dockerfile not found:"
    echo "  $TEMPLATE_DIR/Dockerfile"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/ca-server-config.yaml" ]; then
    echo "Error: CA configuration template not found:"
    echo "  $TEMPLATE_DIR/ca-server-config.yaml"
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo
    echo "Run:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

if docker inspect "$VNFM_NAME" >/dev/null 2>&1; then
    echo "Error: VNFM container '${VNFM_NAME}' already exists."
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    exit 1
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p \
    "$CA_HOST_DATA_DIR" \
    "$ORDERER_HOST_DATA_DIR"

# ============================================================
# Generate CA configuration
# ============================================================

cp \
    "$TEMPLATE_DIR/ca-server-config.yaml" \
    "$CA_HOST_DATA_DIR/fabric-ca-server-config.yaml"

# ============================================================
# Build VNFM image
# ============================================================

IMAGE_NAME="blockchain-vnfm:latest"

docker build \
    -t "$IMAGE_NAME" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:
  ${VNFM_NAME}:
    image: ${IMAGE_NAME}

    container_name: ${VNFM_NAME}

    hostname: ${VNFM_NAME}

    privileged: true

    environment:
      VNFM_NAME: "${VNFM_NAME}"
      VNFM_IP: "${VNFM_IP}"
      CA_IP: "${CA_IP}"
      ORDERER_IP: "${ORDERER_IP}"
      XIT_NETWORK: "${XIT_NETWORK}"

      VNFM_STATE_DIR: "${VNFM_STATE_DIR}"

      HOST_CA_DATA_DIR: "${CA_HOST_DATA_DIR}"
      HOST_ORDERER_DATA_DIR: "${ORDERER_HOST_DATA_DIR}"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${BUILD_DIR}:${VNFM_STATE_DIR}

    networks:
      xit:
        ipv4_address: ${VNFM_IP}

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
# Generate manual CA launcher
#
# Kept for debugging, although normal startup is now automatic.
# ============================================================

cat > "$BUILD_DIR/start-ca.sh" <<EOF
#!/bin/bash

set -e

docker exec \
    ${VNFM_NAME} \
    /opt/vnfm/start-ca.sh
EOF

chmod +x "$BUILD_DIR/start-ca.sh"

# ============================================================
# Generate manual Orderer launcher
#
# Kept for debugging, although normal startup is now automatic.
# ============================================================

cat > "$BUILD_DIR/start-orderer.sh" <<EOF
#!/bin/bash

set -e

docker exec \
    ${VNFM_NAME} \
    /opt/vnfm/start-orderer.sh
EOF

chmod +x "$BUILD_DIR/start-orderer.sh"

# ============================================================
# Ownership
# ============================================================

chown -R \
    "${HOST_UID}:${HOST_GID}" \
    "$BUILD_DIR"

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNFM generated"
echo "=============================================="
echo
echo "Project root:"
echo "  ${PROJECT_ROOT}"
echo
echo "VNFM:"
echo "  Name       : ${VNFM_NAME}"
echo "  XIT IP     : ${VNFM_IP}"
echo
echo "CA:"
echo "  IP         : ${CA_IP}"
echo "  Host data  : ${CA_HOST_DATA_DIR}"
echo
echo "Orderer:"
echo "  IP         : ${ORDERER_IP}"
echo "  Host data  : ${ORDERER_HOST_DATA_DIR}"
echo
echo "VNFM state:"
echo "  Container  : ${VNFM_STATE_DIR}"
echo
echo "Startup:"
echo "  CA         : automatic"
echo "  Orderer    : automatic"
echo
echo "=============================================="