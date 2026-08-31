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

# Fabric peer addressing follows the existing XIT allocation:
# peer 1 = 10.10.0.101
# peer 2 = 10.10.0.102
# ...
FABRIC_PEER_IP="10.10.0.$((100 + INSTANCE))"

# ============================================================
# Validation
# ============================================================

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: VNF template directory not found:"
    echo "  $TEMPLATE_DIR"
    exit 1
fi

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

if [ -d "$BUILD_DIR" ]; then
    echo "Error: VNF instance ${INSTANCE} already exists:"
    echo "  $BUILD_DIR"
    exit 1
fi

# ============================================================
# Prepare build directory
# ============================================================

mkdir -p "$BUILD_DIR"

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
      FABRIC_PEER: ${FABRIC_PEER}
      FABRIC_PEER_IP: ${FABRIC_PEER_IP}

    networks:
      oam:
        ipv4_address: ${VNF_OAM_IP}

      xit:
        ipv4_address: 10.10.0.$((150 + INSTANCE))

networks:
  oam:
    external: true
    name: ${OAM_NETWORK}

  xit:
    external: true
    name: ${XIT_NETWORK}
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
echo "  VNF IP       : 10.10.0.$((150 + INSTANCE))"
echo
echo "Fabric:"
echo "  Peer         : ${FABRIC_PEER}"
echo "  Peer IP      : ${FABRIC_PEER_IP}"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo