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

TOPOLOGY_FILE="$PROJECT_ROOT/build/fabric-network/topology.json"

# ============================================================
# Instance configuration
# ============================================================

VNF_ID="vnf-${INSTANCE}"
GNB_ID="gnb-${INSTANCE}"
GNB_CONTAINER="nr_gnb_${INSTANCE}"
VNF_CONTAINER="vnf-${INSTANCE}"

FABRIC_PEER="fabric-peer-${INSTANCE}"

# ============================================================
# Network configuration
# ============================================================

OAM_NETWORK="OAM-${INSTANCE}"
XIT_NETWORK="XIT"

VNF_OAM_IP="10.20.${INSTANCE}.3"
VNF_XIT_IP="10.10.0.$((150 + INSTANCE))"

# Fabric peer addressing:
# peer 1 = 10.10.0.101
# peer 2 = 10.10.0.102
# ...

FABRIC_PEER_IP="10.10.0.$((100 + INSTANCE))"

# ============================================================
# Fabric configuration
# ============================================================

FABRIC_CHAINCODE="logging"

# ============================================================
# Validation
# ============================================================

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: VNF template directory not found:"
    echo "  $TEMPLATE_DIR"
    exit 1
fi

if [ ! -f "$TOPOLOGY_FILE" ]; then
    echo "Error: Fabric topology not found:"
    echo "  $TOPOLOGY_FILE"
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
# Determine Fabric channel
# ============================================================

FABRIC_CHANNEL="$(
    python3 - "$TOPOLOGY_FILE" "$FABRIC_PEER" <<'PY'
import json
import sys

topology_file = sys.argv[1]
peer_name = sys.argv[2]

with open(topology_file, "r", encoding="utf-8") as f:
    topology = json.load(f)

peer_to_channel = topology.get("peer_to_channel", {})

channel = peer_to_channel.get(peer_name)

if not channel:
    raise SystemExit(
        f"Peer {peer_name} is not assigned to a channel."
    )

print(channel)
PY
)"

if [ -z "$FABRIC_CHANNEL" ]; then
    echo "Error: could not determine Fabric channel for ${FABRIC_PEER}."
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
      VNF_STATE_DIR: /opt/vnf-state

      FABRIC_PEER: ${FABRIC_PEER}
      FABRIC_PEER_IP: ${FABRIC_PEER_IP}
      FABRIC_CHANNEL: ${FABRIC_CHANNEL}
      FABRIC_CHAINCODE: ${FABRIC_CHAINCODE}

      FABRIC_CA_IP: 10.10.0.11
      FABRIC_CA_PORT: 7054

    volumes:
      - ${BUILD_DIR}/state:/opt/vnf-state
      - gnb-${INSTANCE}-logs:/mnt/gnb-logs:ro

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
  gnb-${INSTANCE}-logs:
    external: true
    name: gnb-${INSTANCE}-logs
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
echo "  Channel      : ${FABRIC_CHANNEL}"
echo "  Chaincode    : ${FABRIC_CHAINCODE}"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo