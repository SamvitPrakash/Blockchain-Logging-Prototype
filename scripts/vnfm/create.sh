#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

TEMPLATE_DIR="$PROJECT_ROOT/templates/vnfm"
BUILD_DIR="$PROJECT_ROOT/build/vnfm"

FABRIC_NETWORK_BUILD_DIR="$PROJECT_ROOT/build/fabric-network"
TOPOLOGY_SOURCE="$FABRIC_NETWORK_BUILD_DIR/topology.json"
CHANNEL_SOURCE="$FABRIC_NETWORK_BUILD_DIR/channels"

VNFM_NAME="vnfm"
VNFM_IMAGE="blockchain-vnfm:latest"

ORDERER_NAME="fabric-orderer-1"
ORDERER_IP="10.10.0.20"
VNFM_IP="10.10.0.30"

XIT_NETWORK="XIT"

VNFM_STATE_DIR="/opt/vnfm-state"
VNFM_CREDENTIAL_DIR="/opt/vnfm-credentials"

VNFM_TOPOLOGY_FILE="${VNFM_STATE_DIR}/topology.json"
VNFM_CHANNEL_BLOCK_DIR="${VNFM_STATE_DIR}/channels"

VNFM_TLS_CA="${VNFM_CREDENTIAL_DIR}/ca.crt"
VNFM_TLS_CLIENT_CERT="${VNFM_CREDENTIAL_DIR}/client.crt"
VNFM_TLS_CLIENT_KEY="${VNFM_CREDENTIAL_DIR}/client.key"

VNFM_ADMIN_MSP="${VNFM_CREDENTIAL_DIR}/admin-msp"

VNFM_CREDENTIAL_HOST_DIR="${BUILD_DIR}/credentials"

CA_NAME="fabric-ca"
CA_ENDPOINT="${CA_NAME}:7054"

VNFM_CA_IDENTITY="vnfm"
VNFM_CA_PASSWORD="vnfmpw"

VNFM_ADMIN_IDENTITY="vnfm-admin"
VNFM_ADMIN_PASSWORD="vnfmadminpw"

FABRIC_CA_CLIENT_IMAGE="hyperledger/fabric-ca:1.5.15"

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

if [ ! -f "$TOPOLOGY_SOURCE" ]; then
    echo "Error: topology does not exist:"
    echo "  $TOPOLOGY_SOURCE"
    exit 1
fi

if [ ! -d "$CHANNEL_SOURCE" ]; then
    echo "Error: channel artifacts do not exist:"
    echo "  $CHANNEL_SOURCE"
    exit 1
fi

for file in \
    Dockerfile \
    entrypoint.sh \
    join-orderer.sh \
    manage-chaincode.sh \
    provision-identity.sh
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: VNFM template missing:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if [ ! -d "$TEMPLATE_DIR/chaincode" ]; then
    echo "Error: VNFM chaincode directory missing:"
    echo "  $TEMPLATE_DIR/chaincode"
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist:"
    echo "  $XIT_NETWORK"
    exit 1
fi

if docker inspect "$VNFM_NAME" >/dev/null 2>&1; then
    echo "Error: container already exists:"
    echo "  $VNFM_NAME"
    exit 1
fi

if ! docker inspect "$CA_NAME" >/dev/null 2>&1; then
    echo "Error: Fabric CA container does not exist:"
    echo "  $CA_NAME"
    exit 1
fi

CA_STATUS="$(docker inspect -f '{{.State.Status}}' "$CA_NAME")"

if [ "$CA_STATUS" != "running" ]; then
    echo "Error: Fabric CA is not running:"
    echo "  $CA_NAME"
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: VNFM build directory already exists:"
    echo "  $BUILD_DIR"
    echo
    echo "Remove it before regenerating:"
    echo
    echo "  rm -rf ${BUILD_DIR}"
    exit 1
fi

# ------------------------------------------------------------
# Build directories
# ------------------------------------------------------------

mkdir -p \
    "$BUILD_DIR" \
    "$VNFM_CREDENTIAL_HOST_DIR"

cp "$TOPOLOGY_SOURCE" \
   "$BUILD_DIR/topology.json"

cp -a "$CHANNEL_SOURCE" \
      "$BUILD_DIR/channels"

# ------------------------------------------------------------
# Provision identities
# ------------------------------------------------------------

echo
echo "=============================================="
echo " Provisioning VNFM identities"
echo "=============================================="
echo

"$TEMPLATE_DIR/provision-identity.sh" \
    "$VNFM_CREDENTIAL_HOST_DIR" \
    "$CA_ENDPOINT" \
    "$VNFM_CA_IDENTITY" \
    "$VNFM_CA_PASSWORD" \
    "$VNFM_ADMIN_IDENTITY" \
    "$VNFM_ADMIN_PASSWORD" \
    "$FABRIC_CA_CLIENT_IMAGE"

# ------------------------------------------------------------
# Validate generated credentials
# ------------------------------------------------------------

for file in \
    ca.crt \
    client.crt \
    client.key
do
    if [ ! -s "$VNFM_CREDENTIAL_HOST_DIR/$file" ]; then
        echo "Error: missing VNFM credential:"
        echo "  $VNFM_CREDENTIAL_HOST_DIR/$file"
        exit 1
    fi
done

if [ ! -d "$VNFM_CREDENTIAL_HOST_DIR/admin-msp" ]; then
    echo "Error: VNFM admin MSP was not generated:"
    echo "  $VNFM_CREDENTIAL_HOST_DIR/admin-msp"
    exit 1
fi

if [ ! -s "$VNFM_CREDENTIAL_HOST_DIR/admin-msp/signcerts/cert.pem" ]; then
    echo "Error: VNFM admin certificate was not generated."
    exit 1
fi

# ------------------------------------------------------------
# Build image
# ------------------------------------------------------------

echo
echo "=============================================="
echo " Building VNFM"
echo "=============================================="
echo

docker build \
    -t "$VNFM_IMAGE" \
    "$TEMPLATE_DIR"

# ------------------------------------------------------------
# Compose
# ------------------------------------------------------------

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  vnfm:
    image: ${VNFM_IMAGE}

    container_name: ${VNFM_NAME}
    hostname: ${VNFM_NAME}

    environment:

      VNFM_NAME: "${VNFM_NAME}"

      VNFM_MSP_ID: "Org1MSP"
      VNFM_MSPCONFIGPATH: "${VNFM_ADMIN_MSP}"

      VNFM_ORDERER_NAME: "${ORDERER_NAME}"
      VNFM_ORDERER_ENDPOINT: "${ORDERER_NAME}:7050"
      VNFM_ORDERER_ADMIN_ENDPOINT: "${ORDERER_NAME}:9443"

      VNFM_TOPOLOGY_FILE: "${VNFM_TOPOLOGY_FILE}"
      VNFM_CHANNEL_BLOCK_DIR: "${VNFM_CHANNEL_BLOCK_DIR}"

      VNFM_TLS_CA: "${VNFM_TLS_CA}"
      VNFM_TLS_CLIENT_CERT: "${VNFM_TLS_CLIENT_CERT}"
      VNFM_TLS_CLIENT_KEY: "${VNFM_TLS_CLIENT_KEY}"

      VNFM_CHAINCODE_NAME: "logging"
      VNFM_CHAINCODE_VERSION: "1.0"
      VNFM_CHAINCODE_SEQUENCE: "1"
      VNFM_CHAINCODE_PATH: "/opt/vnfm/chaincode"

      VNFM_WAIT_INTERVAL: "2"
      VNFM_WAIT_TIMEOUT: "120"

    volumes:

      - ${BUILD_DIR}:${VNFM_STATE_DIR}:ro
      - ${VNFM_CREDENTIAL_HOST_DIR}:${VNFM_CREDENTIAL_DIR}:ro

    networks:

      xit:
        ipv4_address: ${VNFM_IP}

    restart: unless-stopped

networks:

  xit:
    external: true
    name: ${XIT_NETWORK}
EOF

# ------------------------------------------------------------
# Validate compose
# ------------------------------------------------------------

docker compose \
    -f "$BUILD_DIR/compose.yaml" \
    config >/dev/null

echo
echo "=============================================="
echo " VNFM generated"
echo "=============================================="
echo

echo "Compose:"
echo "  $BUILD_DIR/compose.yaml"

echo