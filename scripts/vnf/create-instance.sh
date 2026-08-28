#!/bin/bash

set -e

# ============================================================
# VNF Instance Generator
# ============================================================

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEMPLATE_DIR="$PROJECT_ROOT/templates/vnf"
BUILD_DIR="$PROJECT_ROOT/build/vnf-${INSTANCE}"

# ============================================================
# Naming
# ============================================================

VNF_NAME="vnf-${INSTANCE}"
VNF_CONTAINER="vnf-${INSTANCE}"
PEER_NAME="fabric-peer-${INSTANCE}"

OAM_NETWORK="OAM-${INSTANCE}"
OAM_IP="10.20.${INSTANCE}.3"

XIT_NETWORK="XIT"
PEER_IP="10.10.0.$((100 + INSTANCE))"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TEMPLATE_DIR/Dockerfile" ]; then
    echo "Error: VNF Dockerfile not found:"
    echo "  $TEMPLATE_DIR/Dockerfile"
    exit 1
fi

if docker inspect "$VNF_CONTAINER" >/dev/null 2>&1; then
    echo "Error: VNF container '${VNF_CONTAINER}' already exists."
    exit 1
fi

if docker network inspect "$OAM_NETWORK" >/dev/null 2>&1; then
    :
else
    echo "Error: OAM network '${OAM_NETWORK}' does not exist."
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    echo
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    echo
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    exit 1
fi

# ============================================================
# Create build directory
# ============================================================

mkdir -p "$BUILD_DIR"

# ============================================================
# Build VNF image
# ============================================================

IMAGE_NAME="blockchain-vnf:latest"

docker build \
    -t "$IMAGE_NAME" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:
  ${VNF_CONTAINER}:
    image: ${IMAGE_NAME}
    container_name: ${VNF_CONTAINER}
    hostname: ${VNF_CONTAINER}

    privileged: true

    environment:
      VNF_INSTANCE: "${INSTANCE}"
      VNF_NAME: "${VNF_NAME}"
      OAM_NETWORK: "${OAM_NETWORK}"
      OAM_IP: "${OAM_IP}"
      XIT_NETWORK: "${XIT_NETWORK}"
      PEER_IP: "${PEER_IP}"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

    networks:
      oam:
        ipv4_address: ${OAM_IP}
      xit:
        ipv4_address: 10.10.0.$((50 + INSTANCE))

networks:
  oam:
    external: true
    name: ${OAM_NETWORK}

  xit:
    external: true
    name: ${XIT_NETWORK}
EOF

# ============================================================
# Generate helper for nested peer
# ============================================================

cat > "$BUILD_DIR/start-peer.sh" <<EOF
#!/bin/bash

set -e

export VNF_INSTANCE="${INSTANCE}"
export VNF_NAME="${VNF_NAME}"
export OAM_NETWORK="${OAM_NETWORK}"
export OAM_IP="${OAM_IP}"
export XIT_NETWORK="${XIT_NETWORK}"
export PEER_IP="${PEER_IP}"

exec docker exec \
    ${VNF_CONTAINER} \
    /opt/vnf/start-peer.sh
EOF

chmod +x "$BUILD_DIR/start-peer.sh"

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNF instance generated"
echo "=============================================="
echo
echo "VNF:"
echo "  Name       : ${VNF_NAME}"
echo "  Container  : ${VNF_CONTAINER}"
echo "  OAM        : ${OAM_NETWORK}"
echo "  OAM IP     : ${OAM_IP}"
echo "  XIT IP     : 10.10.0.$((50 + INSTANCE))"
echo
echo "Nested peer:"
echo "  Name       : ${PEER_NAME}"
echo "  XIT IP     : ${PEER_IP}"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo "  ${BUILD_DIR}/start-peer.sh"
echo
echo "Start VNF with:"
echo
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo
echo "Then start nested peer with:"
echo
echo "  ${BUILD_DIR}/start-peer.sh"
echo