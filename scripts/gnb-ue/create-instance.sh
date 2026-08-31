#!/bin/bash

set -e

# ============================================================
# gNB / UE Instance Generator
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

BUILD_DIR="$PROJECT_ROOT/build"

GNB_BUILD_DIR="$BUILD_DIR/gnb-${INSTANCE}"
UE_BUILD_DIR="$BUILD_DIR/ue-${INSTANCE}"

# ============================================================
# Templates / scripts
# ============================================================

GNB_TEMPLATE="$PROJECT_ROOT/templates/gnb/config.yaml"
UE_TEMPLATE="$PROJECT_ROOT/templates/ue/config.yaml"

GNB_INIT="$PROJECT_ROOT/docker_open5gs/ueransim/ueransim-gnb_init.sh"
UE_INIT="$PROJECT_ROOT/docker_open5gs/ueransim/ueransim-ue_init.sh"

# ============================================================
# Docker resources
# ============================================================

GNB_LOG_VOLUME="gnb-${INSTANCE}-logs"

# ============================================================
# Instance configuration
# ============================================================

GNB_CONTAINER="nr_gnb_${INSTANCE}"
UE_CONTAINER="nr_ue_${INSTANCE}"

# ============================================================
# Network configuration
# ============================================================

GNB_IP="172.22.0.$((40 + INSTANCE - 1))"
UE_IP="172.22.0.$((50 + INSTANCE - 1))"

# ============================================================
# 5G configuration
# ============================================================

MCC="001"
MNC="01"
TAC="1"
NCI="$INSTANCE"

AMF_IP="172.22.0.10"

# ============================================================
# Validation
# ============================================================

if [ ! -f "$GNB_TEMPLATE" ]; then
    echo "Error: gNB template not found:"
    echo "  $GNB_TEMPLATE"
    exit 1
fi

if [ ! -f "$UE_TEMPLATE" ]; then
    echo "Error: UE template not found:"
    echo "  $UE_TEMPLATE"
    exit 1
fi

if [ ! -f "$GNB_INIT" ]; then
    echo "Error: gNB init script not found:"
    echo "  $GNB_INIT"
    exit 1
fi

if [ ! -f "$UE_INIT" ]; then
    echo "Error: UE init script not found:"
    echo "  $UE_INIT"
    exit 1
fi

if [ -d "$GNB_BUILD_DIR" ] || [ -d "$UE_BUILD_DIR" ]; then
    echo "Error: instance ${INSTANCE} already exists."
    echo
    [ -d "$GNB_BUILD_DIR" ] && echo "  $GNB_BUILD_DIR"
    [ -d "$UE_BUILD_DIR" ] && echo "  $UE_BUILD_DIR"
    exit 1
fi

# ============================================================
# Create Docker log volume
# ============================================================

if docker volume inspect "$GNB_LOG_VOLUME" >/dev/null 2>&1; then
    echo "Using existing Docker volume: $GNB_LOG_VOLUME"
else
    docker volume create "$GNB_LOG_VOLUME" >/dev/null
    echo "Created Docker volume: $GNB_LOG_VOLUME"
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p "$GNB_BUILD_DIR"
mkdir -p "$UE_BUILD_DIR"

# ============================================================
# Copy initialization scripts
# ============================================================

cp "$GNB_INIT" "$GNB_BUILD_DIR/ueransim-gnb_init.sh"
cp "$UE_INIT" "$UE_BUILD_DIR/ueransim-ue_init.sh"

chmod +x "$GNB_BUILD_DIR/ueransim-gnb_init.sh"
chmod +x "$UE_BUILD_DIR/ueransim-ue_init.sh"

# ============================================================
# Generate gNB configuration
# ============================================================

cp "$GNB_TEMPLATE" "$GNB_BUILD_DIR/ueransim-gnb.yaml"

sed -i \
    -e "s|\${MCC}|${MCC}|g" \
    -e "s|\${MNC}|${MNC}|g" \
    -e "s|\${NCI}|${NCI}|g" \
    -e "s|\${TAC}|${TAC}|g" \
    -e "s|\${GNB_IP}|${GNB_IP}|g" \
    -e "s|\${AMF_IP}|${AMF_IP}|g" \
    "$GNB_BUILD_DIR/ueransim-gnb.yaml"

# ============================================================
# Generate UE configuration
# ============================================================

cp "$UE_TEMPLATE" "$UE_BUILD_DIR/ueransim-ue.yaml"

# ============================================================
# Generate gNB Compose
# ============================================================

cat > "$GNB_BUILD_DIR/compose.yaml" <<EOF
services:
  ${GNB_CONTAINER}:
    image: docker_ueransim
    container_name: ${GNB_CONTAINER}
    stdin_open: true
    tty: true

    volumes:
      - ${GNB_BUILD_DIR}:/mnt/ueransim
      - ${GNB_LOG_VOLUME}:/mnt/gnb-logs
      - /etc/localtime:/etc/localtime:ro

    environment:
      COMPONENT_NAME: ueransim-gnb

    expose:
      - "38412/sctp"
      - "2152/udp"
      - "4997/udp"

    cap_add:
      - NET_ADMIN

    privileged: true

    networks:
      default:
        ipv4_address: ${GNB_IP}

networks:
  default:
    external: true
    name: docker_open5gs_default

volumes:
  ${GNB_LOG_VOLUME}:
    external: true
    name: ${GNB_LOG_VOLUME}
EOF

# ============================================================
# Generate UE Compose
# ============================================================

cat > "$UE_BUILD_DIR/compose.yaml" <<EOF
services:
  ${UE_CONTAINER}:
    image: docker_ueransim
    container_name: ${UE_CONTAINER}
    stdin_open: true
    tty: true

    volumes:
      - ${UE_BUILD_DIR}:/mnt/ueransim
      - /etc/localtime:/etc/localtime:ro

    environment:
      COMPONENT_NAME: ueransim-ue

    expose:
      - "4997/udp"

    cap_add:
      - NET_ADMIN

    privileged: true

    networks:
      default:
        ipv4_address: ${UE_IP}

networks:
  default:
    external: true
    name: docker_open5gs_default
EOF

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " Instance ${INSTANCE} generated"
echo "=============================================="
echo
echo "gNB:"
echo "  Container    : ${GNB_CONTAINER}"
echo "  IP           : ${GNB_IP}"
echo "  MCC          : ${MCC}"
echo "  MNC          : ${MNC}"
echo "  TAC          : ${TAC}"
echo "  NCI          : ${NCI}"
echo "  AMF IP       : ${AMF_IP}"
echo
echo "UE:"
echo "  Container    : ${UE_CONTAINER}"
echo "  IP           : ${UE_IP}"
echo
echo "Logging:"
echo "  Docker volume: ${GNB_LOG_VOLUME}"
echo "  gNB mount     : /mnt/gnb-logs"
echo
echo "Generated:"
echo "  ${GNB_BUILD_DIR}"
echo "  ${UE_BUILD_DIR}"
echo