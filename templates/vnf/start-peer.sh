#!/bin/bash

set -euo pipefail

: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_HOSTNAME:?PEER_HOSTNAME is required}"
: "${PEER_IP:?PEER_IP is required}"
: "${PEER_STATE_DIR:?PEER_STATE_DIR is required}"
: "${HOST_PEER_STATE_DIR:?HOST_PEER_STATE_DIR is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"

PEER_IMAGE="hyperledger/fabric-peer:2.5"
PEER_CONTAINER="${PEER_NAME}"

# PEER_STATE_DIR:
#   Path as seen from inside the VNF container.
#
# HOST_PEER_STATE_DIR:
#   Path as seen by the host Docker daemon.
#
# The nested peer is created by the host Docker daemon because
# the VNF has /var/run/docker.sock mounted into it.

HOST_MSP_DIR="${HOST_PEER_STATE_DIR}/msp"
HOST_TLS_DIR="${HOST_PEER_STATE_DIR}/tls"
HOST_CORE_CONFIG="${HOST_PEER_STATE_DIR}/core.yaml"
HOST_PRODUCTION_DIR="${HOST_PEER_STATE_DIR}/production"

echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="
echo
echo "Peer            : ${PEER_NAME}"
echo "Hostname        : ${PEER_HOSTNAME}"
echo "Peer IP         : ${PEER_IP}"
echo "XIT             : ${XIT_NETWORK}"
echo "VNF state       : ${PEER_STATE_DIR}"
echo "Host peer state : ${HOST_PEER_STATE_DIR}"
echo

# ============================================================
# Validate host-side peer state
# ============================================================

if [ ! -d "${HOST_PEER_STATE_DIR}" ]; then
    echo "Error: host peer state directory does not exist:"
    echo "  ${HOST_PEER_STATE_DIR}"
    exit 1
fi

if [ ! -d "${HOST_MSP_DIR}" ]; then
    echo "Error: host MSP directory does not exist:"
    echo "  ${HOST_MSP_DIR}"
    exit 1
fi

if [ ! -d "${HOST_MSP_DIR}/signcerts" ]; then
    echo "Error: MSP signcerts directory does not exist:"
    echo "  ${HOST_MSP_DIR}/signcerts"
    exit 1
fi

if ! find "${HOST_MSP_DIR}/signcerts" \
    -type f \
    -name '*.pem' \
    -print \
    -quit | grep -q .
then
    echo "Error: no MSP signer certificate found."
    exit 1
fi

if [ ! -d "${HOST_MSP_DIR}/keystore" ]; then
    echo "Error: MSP keystore directory does not exist:"
    echo "  ${HOST_MSP_DIR}/keystore"
    exit 1
fi

if ! find "${HOST_MSP_DIR}/keystore" \
    -type f \
    -name '*_sk' \
    -print \
    -quit | grep -q .
then
    echo "Error: no MSP private key found."
    exit 1
fi

if [ ! -f "${HOST_MSP_DIR}/config.yaml" ]; then
    echo "Error: MSP config.yaml does not exist:"
    echo "  ${HOST_MSP_DIR}/config.yaml"
    exit 1
fi

# ============================================================
# Validate TLS state
# ============================================================

if [ ! -d "${HOST_TLS_DIR}" ]; then
    echo "Error: host TLS directory does not exist:"
    echo "  ${HOST_TLS_DIR}"
    exit 1
fi

for file in server.crt server.key ca.crt; do
    if [ ! -f "${HOST_TLS_DIR}/${file}" ]; then
        echo "Error: missing TLS file:"
        echo "  ${HOST_TLS_DIR}/${file}"
        exit 1
    fi
done

# ============================================================
# Prepare peer filesystem
# ============================================================

mkdir -p "${HOST_PRODUCTION_DIR}"

# ============================================================
# Generate peer configuration
# ============================================================

cat > "${HOST_CORE_CONFIG}" <<EOF
peer:
  id: ${PEER_NAME}
  networkId: dev
  listenAddress: 0.0.0.0:7051
  address: ${PEER_HOSTNAME}:7051
  addressAutoDetect: false

  gossip:
    bootstrap: ${PEER_HOSTNAME}:7051
    externalEndpoint: ${PEER_HOSTNAME}:7051
    endpoint: ${PEER_HOSTNAME}:7051
    useLeaderElection: false
    orgLeader: false

  mspConfigPath: /etc/hyperledger/fabric/msp
  localMspId: Org1MSP

  fileSystemPath: /var/hyperledger/production

  tls:
    enabled: true
    clientAuthRequired: false

    cert:
      file: /etc/hyperledger/fabric/tls/server.crt

    key:
      file: /etc/hyperledger/fabric/tls/server.key

    rootcert:
      file: /etc/hyperledger/fabric/tls/ca.crt

  BCCSP:
    Default: SW

    SW:
      Hash: SHA2
      Security: 256

      FileKeyStore:
        KeyStore: /etc/hyperledger/fabric/msp/keystore

operations:
  listenAddress: 0.0.0.0:9443
  tls:
    enabled: false
EOF

echo "Peer configuration:"
echo "  ${HOST_CORE_CONFIG}"
echo

# ============================================================
# Remove existing peer container
# ============================================================

if docker inspect "${PEER_CONTAINER}" >/dev/null 2>&1; then
    echo "Removing existing peer container..."
    docker rm -f "${PEER_CONTAINER}" >/dev/null
fi

# ============================================================
# Start nested Fabric peer
#
# IMPORTANT:
#
# Docker is using the HOST daemon through:
#
#   /var/run/docker.sock
#
# Therefore every bind source below must be a HOST path.
# ============================================================

echo "Starting Fabric peer..."

docker run \
    -d \
    --name "${PEER_CONTAINER}" \
    --hostname "${PEER_HOSTNAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${PEER_IP}" \
    -v "${HOST_PEER_STATE_DIR}:/etc/hyperledger/fabric:rw" \
    -v "${HOST_PRODUCTION_DIR}:/var/hyperledger/production:rw" \
    -e FABRIC_CFG_PATH=/etc/hyperledger/fabric \
    -e CORE_PEER_ID="${PEER_NAME}" \
    -e CORE_PEER_ADDRESS="${PEER_HOSTNAME}:7051" \
    -e CORE_PEER_LISTENADDRESS="0.0.0.0:7051" \
    -e CORE_PEER_LOCALMSPID="Org1MSP" \
    -e CORE_PEER_MSPCONFIGPATH="/etc/hyperledger/fabric/msp" \
    -e CORE_PEER_TLS_ENABLED=true \
    -e CORE_PEER_TLS_CERT_FILE="/etc/hyperledger/fabric/tls/server.crt" \
    -e CORE_PEER_TLS_KEY_FILE="/etc/hyperledger/fabric/tls/server.key" \
    -e CORE_PEER_TLS_ROOTCERT_FILE="/etc/hyperledger/fabric/tls/ca.crt" \
    "${PEER_IMAGE}" \
    peer node start

echo
echo "Nested Fabric peer started."
echo
echo "Container:"
docker ps --filter "name=${PEER_CONTAINER}"

echo
echo "Check logs with:"
echo
echo "  docker logs ${PEER_CONTAINER}"
echo