#!/bin/bash

set -e

# ============================================================
# FABRIC-BOOTSTRAP Generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

TEMPLATE_DIR="$PROJECT_ROOT/templates/fabric-bootstrap"
BUILD_DIR="$PROJECT_ROOT/build/fabric-bootstrap"

VNFM_NAME="fabric-bootstrap"
CA_NAME="fabric-ca"
ORDERER_NAME="fabric-orderer-1"

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

VNFM_STATE_DIR="/opt/fabric-bootstrap-state"

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
    echo "Error: FABRIC-BOOTSTRAP Dockerfile not found:"
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

for container in \
    "$VNFM_NAME" \
    "$CA_NAME" \
    "$ORDERER_NAME"
do
    if docker inspect "$container" >/dev/null 2>&1; then
        echo "Error: container '${container}' already exists."
        exit 1
    fi
done

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
# Build FABRIC-BOOTSTRAP image
# ============================================================

IMAGE_NAME="blockchain-fabric-bootstrap:latest"

docker build \
    -t "$IMAGE_NAME" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  # ==========================================================
  # Fabric CA
  # ==========================================================

  ${CA_NAME}:
    image: hyperledger/fabric-ca:1.5.17

    container_name: ${CA_NAME}
    hostname: ${CA_NAME}

    environment:
      FABRIC_CA_HOME: /etc/hyperledger/fabric-ca-server

    command:
      - fabric-ca-server
      - start
      - -c
      - /etc/hyperledger/fabric-ca-server/fabric-ca-server-config.yaml
      - -b
      - admin:adminpw

    volumes:
      - ${CA_HOST_DATA_DIR}:/etc/hyperledger/fabric-ca-server

    networks:
      xit:
        ipv4_address: ${CA_IP}

    healthcheck:
      test:
        - CMD
        - fabric-ca-client
        - getcainfo
        - -u
        - http://127.0.0.1:7054
      interval: 2s
      timeout: 3s
      retries: 30
      start_period: 3s

    restart: unless-stopped

  # ==========================================================
  # Fabric bootstrap
  # ==========================================================

  ${VNFM_NAME}:
    image: ${IMAGE_NAME}

    container_name: ${VNFM_NAME}
    hostname: ${VNFM_NAME}

    environment:
      VNFM_NAME: "${VNFM_NAME}"
      VNFM_IP: "${VNFM_IP}"
      CA_IP: "${CA_IP}"
      ORDERER_IP: "${ORDERER_IP}"
      XIT_NETWORK: "${XIT_NETWORK}"
      VNFM_STATE_DIR: "${VNFM_STATE_DIR}"
      HOST_ORDERER_DATA_DIR: "${VNFM_STATE_DIR}/orderer"

    volumes:
      - ${BUILD_DIR}:${VNFM_STATE_DIR}

    depends_on:
      ${CA_NAME}:
        condition: service_healthy

    networks:
      xit:
        ipv4_address: ${VNFM_IP}

    restart: "no"

  # ==========================================================
  # Fabric orderer
  # ==========================================================

  ${ORDERER_NAME}:
    image: hyperledger/fabric-orderer:2.5.16

    container_name: ${ORDERER_NAME}
    hostname: ${ORDERER_NAME}

    depends_on:
      ${VNFM_NAME}:
        condition: service_completed_successfully

    environment:
      FABRIC_CFG_PATH: "/etc/hyperledger/fabric"

      ORDERER_GENERAL_LISTENADDRESS: "0.0.0.0"
      ORDERER_GENERAL_LISTENPORT: "7050"

      ORDERER_GENERAL_LOCALMSPID: "OrdererMSP"
      ORDERER_GENERAL_LOCALMSPDIR: "/var/hyperledger/orderer/msp"

      ORDERER_GENERAL_BOOTSTRAPMETHOD: "none"

      ORDERER_CHANNELPARTICIPATION_ENABLED: "true"

      ORDERER_GENERAL_TLS_ENABLED: "true"
      ORDERER_GENERAL_TLS_PRIVATEKEY: "/var/hyperledger/orderer/tls/server.key"
      ORDERER_GENERAL_TLS_CERTIFICATE: "/var/hyperledger/orderer/tls/server.crt"
      ORDERER_GENERAL_TLS_ROOTCAS: "[/var/hyperledger/orderer/tls/ca.crt]"

      ORDERER_GENERAL_CLUSTER_LISTENADDRESS: "0.0.0.0"
      ORDERER_GENERAL_CLUSTER_LISTENPORT: "7051"

      ORDERER_GENERAL_CLUSTER_SERVERCERTIFICATE: "/var/hyperledger/orderer/tls/server.crt"
      ORDERER_GENERAL_CLUSTER_SERVERPRIVATEKEY: "/var/hyperledger/orderer/tls/server.key"
      ORDERER_GENERAL_CLUSTER_ROOTCAS: "[/var/hyperledger/orderer/tls/ca.crt]"

      ORDERER_FILELEDGER_LOCATION: "/var/hyperledger/orderer/production"

    volumes:
      - ${ORDERER_HOST_DATA_DIR}:/var/hyperledger/orderer

    networks:
      xit:
        ipv4_address: ${ORDERER_IP}

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
echo " FABRIC-BOOTSTRAP generated"
echo "=============================================="
echo

echo "Project root:"
echo "  ${PROJECT_ROOT}"
echo

echo "Fabric CA:"
echo "  Name       : ${CA_NAME}"
echo "  IP         : ${CA_IP}"
echo "  Host data  : ${CA_HOST_DATA_DIR}"
echo

echo "FABRIC-BOOTSTRAP:"
echo "  Name       : ${VNFM_NAME}"
echo "  IP         : ${VNFM_IP}"
echo

echo "Fabric orderer:"
echo "  Name       : ${ORDERER_NAME}"
echo "  IP         : ${ORDERER_IP}"
echo "  Host data  : ${ORDERER_HOST_DATA_DIR}"
echo

echo "Compose:"
echo "  ${BUILD_DIR}/compose.yaml"
echo

echo "Start with:"
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo

echo "=============================================="