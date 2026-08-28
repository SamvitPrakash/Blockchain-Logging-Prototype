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
VNF_XIT_IP="10.10.0.$((50 + INSTANCE))"
PEER_IP="10.10.0.$((100 + INSTANCE))"

CA_IP="10.10.0.11"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$TEMPLATE_DIR/Dockerfile" ]; then
    echo "Error: VNF Dockerfile not found:"
    echo "  $TEMPLATE_DIR/Dockerfile"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/entrypoint.sh" ]; then
    echo "Error: VNF entrypoint not found:"
    echo "  $TEMPLATE_DIR/entrypoint.sh"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/start-peer.sh" ]; then
    echo "Error: nested peer script not found:"
    echo "  $TEMPLATE_DIR/start-peer.sh"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/register-peer.sh" ]; then
    echo "Error: peer registration script not found:"
    echo "  $TEMPLATE_DIR/register-peer.sh"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/enroll-peer.sh" ]; then
    echo "Error: peer enrollment script not found:"
    echo "  $TEMPLATE_DIR/enroll-peer.sh"
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
# Create persistent peer state directory
# ============================================================

mkdir -p "$BUILD_DIR/peer"

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

cat > "$BUILD_DIR/compose.yaml" <<COMPOSE
services:
  ${VNF_CONTAINER}:
    image: ${IMAGE_NAME}
    container_name: ${VNF_CONTAINER}
    hostname: ${VNF_CONTAINER}

    privileged: true

    environment:
      VNF_INSTANCE: "${INSTANCE}"
      VNF_NAME: "${VNF_NAME}"
      VNF_STATE_DIR: /opt/vnf-state

      OAM_NETWORK: "${OAM_NETWORK}"
      OAM_IP: "${OAM_IP}"

      XIT_NETWORK: "${XIT_NETWORK}"
      VNF_XIT_IP: "${VNF_XIT_IP}"

      PEER_NAME: "${PEER_NAME}"
      PEER_HOSTNAME: "${PEER_NAME}"
      PEER_IP: "${PEER_IP}"

      CA_NAME: "ca"
      CA_IP: "${CA_IP}"

      PEER_SECRET: "peer${INSTANCE}pw"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${BUILD_DIR}:/opt/vnf-state

    networks:
      oam:
        ipv4_address: ${OAM_IP}

      xit:
        ipv4_address: ${VNF_XIT_IP}

networks:
  oam:
    external: true
    name: ${OAM_NETWORK}

  xit:
    external: true
    name: ${XIT_NETWORK}
COMPOSE

# ============================================================
# Host-side peer wrapper
# ============================================================

cat > "$BUILD_DIR/start-peer.sh" <<STARTPEER
#!/bin/bash

set -e

VNF_CONTAINER="${VNF_CONTAINER}"

echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="
echo
echo "VNF          : ${VNF_NAME}"
echo "Peer         : ${PEER_NAME}"
echo "Peer IP      : ${PEER_IP}"
echo "XIT          : ${XIT_NETWORK}"
echo

if ! docker inspect \
    --format '{{.State.Running}}' \
    "${VNF_CONTAINER}" 2>/dev/null | grep -q '^true$'; then

    echo "Error: VNF container '${VNF_CONTAINER}' is not running."
    echo
    echo "Start it with:"
    echo
    echo "  docker compose -f build/vnf-${INSTANCE}/compose.yaml up -d"
    exit 1
fi

exec docker exec \
    "${VNF_CONTAINER}" \
    /opt/vnf/start-peer.sh
STARTPEER

chmod +x "$BUILD_DIR/start-peer.sh"

# ============================================================
# Host-side peer registration wrapper
# ============================================================

cat > "$BUILD_DIR/register-peer.sh" <<REGISTERPEER
#!/bin/bash

set -e

VNF_CONTAINER="${VNF_CONTAINER}"

echo "=============================================="
echo " Registering nested Fabric peer"
echo "=============================================="
echo

if ! docker inspect \
    --format '{{.State.Running}}' \
    "${VNF_CONTAINER}" 2>/dev/null | grep -q '^true$'; then

    echo "Error: VNF container '${VNF_CONTAINER}' is not running."
    exit 1
fi

exec docker exec \
    "${VNF_CONTAINER}" \
    /opt/vnf/register-peer.sh
REGISTERPEER

chmod +x "$BUILD_DIR/register-peer.sh"

# ============================================================
# Host-side peer enrollment wrapper
# ============================================================

cat > "$BUILD_DIR/enroll-peer.sh" <<ENROLLPEER
#!/bin/bash

set -e

VNF_CONTAINER="${VNF_CONTAINER}"

echo "=============================================="
echo " Enrolling nested Fabric peer"
echo "=============================================="
echo

if ! docker inspect \
    --format '{{.State.Running}}' \
    "${VNF_CONTAINER}" 2>/dev/null | grep -q '^true$'; then

    echo "Error: VNF container '${VNF_CONTAINER}' is not running."
    exit 1
fi

exec docker exec \
    "${VNF_CONTAINER}" \
    /opt/vnf/enroll-peer.sh
ENROLLPEER

chmod +x "$BUILD_DIR/enroll-peer.sh"

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
echo "  XIT IP     : ${VNF_XIT_IP}"
echo
echo "Nested peer:"
echo "  Name       : ${PEER_NAME}"
echo "  XIT IP     : ${PEER_IP}"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo "  ${BUILD_DIR}/register-peer.sh"
echo "  ${BUILD_DIR}/enroll-peer.sh"
echo "  ${BUILD_DIR}/start-peer.sh"
echo
echo "Peer state:"
echo "  ${BUILD_DIR}/peer/"
echo
echo "Start VNF with:"
echo
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo
echo "Register peer with:"
echo
echo "  ${BUILD_DIR}/register-peer.sh"
echo
echo "Enroll peer with:"
echo
echo "  ${BUILD_DIR}/enroll-peer.sh"
echo
echo "Start nested peer with:"
echo
echo "  ${BUILD_DIR}/start-peer.sh"
echo
