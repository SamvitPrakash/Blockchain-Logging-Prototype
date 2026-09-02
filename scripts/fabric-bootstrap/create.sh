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
ORDERER_NAME="fabric-orderer-1"

# ============================================================
# Network addressing
# ============================================================

VNFM_IP="10.10.0.10"
CA_IP="10.10.0.11"
ORDERER_IP="10.10.0.20"

XIT_NETWORK="XIT"

# ============================================================
# Host/container paths
# ============================================================

ORDERER_HOST_DATA_DIR="$BUILD_DIR/orderer"

VNFM_STATE_DIR="/opt/fabric-bootstrap-state"

# ============================================================
# Host ownership
# ============================================================

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

for file in \
    Dockerfile \
    entrypoint.sh \
    enroll-orderer.sh
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: FABRIC-BOOTSTRAP template file not found:"
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

for container in \
    "$VNFM_NAME" \
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
    echo
    echo "Remove it before regenerating:"
    echo
    echo "  rm -rf ${BUILD_DIR}"
    echo
    exit 1
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p "$BUILD_DIR"
mkdir -p "$ORDERER_HOST_DATA_DIR"

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
  # Fabric bootstrap
  #
  # Short-lived initialization container.
  #
  # Fabric CA is external to this Compose project.
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

    networks:
      xit:
        ipv4_address: ${VNFM_IP}

    restart: "no"

  # ==========================================================
  # Fabric orderer
  #
  # Starts only after bootstrap exits successfully.
  #
  # Architecture:
  #
  #   7050  Fabric orderer endpoint
  #   7051  Raft cluster endpoint
  #   9443  Admin / channel participation endpoint
  #
  # There is intentionally only ONE orderer.
  # ==========================================================

  ${ORDERER_NAME}:
    image: hyperledger/fabric-orderer:2.5.16

    container_name: ${ORDERER_NAME}
    hostname: ${ORDERER_NAME}

    depends_on:
      ${VNFM_NAME}:
        condition: service_completed_successfully

    environment:

      # --------------------------------------------------------
      # Fabric configuration
      # --------------------------------------------------------

      FABRIC_CFG_PATH: "/etc/hyperledger/fabric"

      # --------------------------------------------------------
      # General orderer listener
      # --------------------------------------------------------

      ORDERER_GENERAL_LISTENADDRESS: "0.0.0.0"
      ORDERER_GENERAL_LISTENPORT: "7050"

      # --------------------------------------------------------
      # Orderer identity
      # --------------------------------------------------------

      ORDERER_GENERAL_LOCALMSPID: "OrdererMSP"
      ORDERER_GENERAL_LOCALMSPDIR: "/var/hyperledger/orderer/msp"

      # --------------------------------------------------------
      # Channel participation architecture
      #
      # No system channel is used.
      # Channels are joined through the participation API.
      # --------------------------------------------------------

      ORDERER_GENERAL_BOOTSTRAPMETHOD: "none"
      ORDERER_CHANNELPARTICIPATION_ENABLED: "true"

      # --------------------------------------------------------
      # General TLS
      # --------------------------------------------------------

      ORDERER_GENERAL_TLS_ENABLED: "true"

      ORDERER_GENERAL_TLS_PRIVATEKEY: "/var/hyperledger/orderer/tls/server.key"
      ORDERER_GENERAL_TLS_CERTIFICATE: "/var/hyperledger/orderer/tls/server.crt"
      ORDERER_GENERAL_TLS_ROOTCAS: "[/var/hyperledger/orderer/tls/ca.crt]"

      # --------------------------------------------------------
      # Raft cluster listener
      #
      # Kept separate from the admin API.
      # --------------------------------------------------------

      ORDERER_GENERAL_CLUSTER_LISTENADDRESS: "0.0.0.0"
      ORDERER_GENERAL_CLUSTER_LISTENPORT: "7051"

      ORDERER_GENERAL_CLUSTER_SERVERCERTIFICATE: "/var/hyperledger/orderer/tls/server.crt"
      ORDERER_GENERAL_CLUSTER_SERVERPRIVATEKEY: "/var/hyperledger/orderer/tls/server.key"
      ORDERER_GENERAL_CLUSTER_ROOTCAS: "[/var/hyperledger/orderer/tls/ca.crt]"

      # --------------------------------------------------------
      # Orderer Admin / Channel Participation API
      #
      # Fabric's channel participation API uses the Admin
      # listener.
      #
      # The listener must be reachable from the XIT network.
      # --------------------------------------------------------

      ORDERER_ADMIN_LISTENADDRESS: "0.0.0.0:9443"

      ORDERER_ADMIN_TLS_ENABLED: "true"

      ORDERER_ADMIN_TLS_CERTIFICATE: "/var/hyperledger/orderer/tls/server.crt"
      ORDERER_ADMIN_TLS_PRIVATEKEY: "/var/hyperledger/orderer/tls/server.key"

      ORDERER_ADMIN_TLS_CLIENTAUTHREQUIRED: "true"

      ORDERER_ADMIN_TLS_CLIENTROOTCAS: "[/var/hyperledger/orderer/tls/ca.crt]"

      # --------------------------------------------------------
      # Ledger storage
      # --------------------------------------------------------

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

echo "Bootstrap:"
echo "  Name       : ${VNFM_NAME}"
echo "  IP         : ${VNFM_IP}"
echo

echo "Fabric CA:"
echo "  Name       : fabric-ca"
echo "  IP         : ${CA_IP}"
echo "  External to this Compose project"
echo

echo "Fabric orderer:"
echo "  Name       : ${ORDERER_NAME}"
echo "  IP         : ${ORDERER_IP}"
echo "  Host data  : ${ORDERER_HOST_DATA_DIR}"
echo

echo "Orderer endpoints:"
echo "  Fabric      : 7050"
echo "  Cluster     : 7051"
echo "  Admin API   : 9443"
echo

echo "Compose:"
echo "  ${BUILD_DIR}/compose.yaml"
echo

echo "Start with:"
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo

echo "=============================================="