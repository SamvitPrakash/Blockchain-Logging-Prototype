#!/bin/bash

set -e

# ============================================================
# VNF Generator
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
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

BUILD_DIR="$PROJECT_ROOT/build/vnf-${INSTANCE}"
TEMPLATE_DIR="$PROJECT_ROOT/templates/vnf"

VNF_STATE_DIR="$BUILD_DIR/state"

# ============================================================
# Instance configuration
# ============================================================

VNF_ID="vnf-${INSTANCE}"
GNB_ID="gnb-${INSTANCE}"
GNB_CONTAINER="nr_gnb_${INSTANCE}"
VNF_CONTAINER="vnf-${INSTANCE}"
FABRIC_PEER="fabric-peer-${INSTANCE}"

OAM_NETWORK="OAM-${INSTANCE}"
XIT_NETWORK="XIT"

VNF_OAM_IP="10.20.${INSTANCE}.3"
VNF_XIT_IP="10.10.0.$((150 + INSTANCE))"

FABRIC_PEER_IP="10.10.0.$((100 + INSTANCE))"

# ============================================================
# Log volume
# ============================================================

GNB_LOG_VOLUME="gnb-${INSTANCE}-logs"

# ============================================================
# Fabric CA
# ============================================================

FABRIC_CA_IP="10.10.0.11"
FABRIC_CA_PORT="7054"

# ============================================================
# VNF credentials
# ============================================================

VNF_SECRET="vnfpw"

# ============================================================
# Validation
# ============================================================

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: VNF template directory not found:"
    echo "  $TEMPLATE_DIR"
    exit 1
fi

for file in \
    Dockerfile \
    entrypoint.sh \
    register-vnf.sh \
    enroll-vnf.sh \
    requirements.txt \
    src/main.py
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: VNF template file not found:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if ! docker network inspect "$OAM_NETWORK" >/dev/null 2>&1; then
    echo "Error: OAM network '${OAM_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network '${XIT_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    exit 1
fi

if ! docker volume inspect "$GNB_LOG_VOLUME" >/dev/null 2>&1; then
    echo "Error: gNB log volume '${GNB_LOG_VOLUME}' does not exist."
    echo
    echo "Create the corresponding gNB instance first."
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: VNF instance ${INSTANCE} already exists:"
    echo "  $BUILD_DIR"
    exit 1
fi

# ============================================================
# Prepare build directory
# ============================================================

mkdir -p "$VNF_STATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:
  ${VNF_CONTAINER}:
    build:
      context: ${TEMPLATE_DIR}
      dockerfile: Dockerfile

    image: blockchain-logging-vnf
    container_name: ${VNF_CONTAINER}

    environment:
      VNF_ID: ${VNF_ID}
      GNB_ID: ${GNB_ID}
      VNF_STATE_DIR: /opt/vnf-state

      FABRIC_PEER: ${FABRIC_PEER}
      FABRIC_PEER_IP: ${FABRIC_PEER_IP}

      FABRIC_CA_IP: ${FABRIC_CA_IP}
      FABRIC_CA_PORT: ${FABRIC_CA_PORT}

      VNF_SECRET: ${VNF_SECRET}

    volumes:
      - ${GNB_LOG_VOLUME}:/mnt/gnb-logs:ro
      - ${VNF_STATE_DIR}:/opt/vnf-state

    networks:
      oam:
        ipv4_address: ${VNF_OAM_IP}

      xit:
        ipv4_address: ${VNF_XIT_IP}

networks:
  oam:
    external: true
    name: ${OAM_NETWORK}

  xit:
    external: true
    name: ${XIT_NETWORK}

volumes:
  ${GNB_LOG_VOLUME}:
    external: true
    name: ${GNB_LOG_VOLUME}
EOF

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNF instance ${INSTANCE} generated"
echo "=============================================="
echo
echo "VNF:"
echo "  Container    : ${VNF_CONTAINER}"
echo "  VNF ID       : ${VNF_ID}"
echo "  gNB          : ${GNB_CONTAINER}"
echo "  gNB ID       : ${GNB_ID}"
echo
echo "OAM:"
echo "  Network      : ${OAM_NETWORK}"
echo "  VNF IP       : ${VNF_OAM_IP}"
echo
echo "XIT:"
echo "  Network      : ${XIT_NETWORK}"
echo "  VNF IP       : ${VNF_XIT_IP}"
echo
echo "Fabric:"
echo "  Peer         : ${FABRIC_PEER}"
echo "  Peer IP      : ${FABRIC_PEER_IP}"
echo
echo "Fabric CA:"
echo "  Address      : ${FABRIC_CA_IP}:${FABRIC_CA_PORT}"
echo
echo "Logs:"
echo "  Volume       : ${GNB_LOG_VOLUME}"
echo "  Mount        : /mnt/gnb-logs (read-only)"
echo
echo "VNF state:"
echo "  Host         : ${VNF_STATE_DIR}"
echo "  Container    : /opt/vnf-state"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo