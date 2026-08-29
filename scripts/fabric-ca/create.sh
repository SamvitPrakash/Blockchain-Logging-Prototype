#!/bin/bash

set -euo pipefail

# ============================================================
# FABRIC-CA Generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEMPLATE_DIR="$PROJECT_ROOT/templates/fabric-ca"
BUILD_DIR="$PROJECT_ROOT/build/fabric-ca"

CA_NAME="fabric-ca"
CA_IMAGE="blockchain-fabric-ca:latest"

XIT_NETWORK="XIT"
CA_IP="10.10.0.11"

CA_STATE_DIR="/opt/fabric-ca-state"
HOST_CA_STATE_DIR="$BUILD_DIR/ca"

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# ============================================================
# Validation
# ============================================================

for file in \
    Dockerfile \
    ca-server-config.yaml
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: FABRIC-CA template file not found:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network '${XIT_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    echo
    exit 1
fi

if docker inspect "$CA_NAME" >/dev/null 2>&1; then
    echo "Error: Fabric CA container '${CA_NAME}' already exists."
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    echo
    echo "Remove it first if you want to regenerate the CA:"
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
    "$HOST_CA_STATE_DIR"

# ============================================================
# Build FABRIC-CA image
# ============================================================

docker build \
    -t "$CA_IMAGE" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  ${CA_NAME}:
    image: ${CA_IMAGE}

    container_name: ${CA_NAME}
    hostname: ${CA_NAME}

    environment:
      FABRIC_CA_HOME: "${CA_STATE_DIR}"

    volumes:
      - ${HOST_CA_STATE_DIR}:${CA_STATE_DIR}

    networks:
      xit:
        ipv4_address: ${CA_IP}

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
echo " FABRIC-CA generated"
echo "=============================================="
echo

echo "CA:"
echo "  Name       : ${CA_NAME}"
echo "  Image      : ${CA_IMAGE}"
echo "  IP         : ${CA_IP}"
echo

echo "State:"
echo "  Container  : ${CA_STATE_DIR}"
echo "  Host       : ${HOST_CA_STATE_DIR}"
echo

echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo

echo "Start with:"
echo
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo