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

MSP_DIR="${PEER_STATE_DIR}/msp"
TLS_DIR="${PEER_STATE_DIR}/tls"
CORE_CONFIG="${PEER_STATE_DIR}/core.yaml"
PRODUCTION_DIR="${PEER_STATE_DIR}/production"

echo "=============================================="
echo " Starting nested Fabric peer"
echo "=============================================="
echo
echo "Peer            : ${PEER_NAME}"
echo "Hostname        : ${PEER_HOSTNAME}"
echo "Peer IP         : ${PEER_IP}"
echo "XIT             : ${XIT_NETWORK}"
echo "FABRIC-ENROLL state       : ${PEER_STATE_DIR}"
echo "Host peer state : ${HOST_PEER_STATE_DIR}"
echo

# ============================================================
# Validate FABRIC-ENROLL-side peer state
# ============================================================

if [ ! -d "${PEER_STATE_DIR}" ]; then
    echo "Error: peer state directory does not exist:"
    echo "  ${PEER_STATE_DIR}"
    exit 1
fi

if [ ! -d "${MSP_DIR}" ]; then
    echo "Error: MSP directory does not exist:"
    echo "  ${MSP_DIR}"
    exit 1
fi

if [ ! -d "${MSP_DIR}/signcerts" ]; then
    echo "Error: MSP signcerts directory does not exist:"
    echo "  ${MSP_DIR}/signcerts"
    exit 1
fi

if ! find "${MSP_DIR}/signcerts" \
    -type f \
    -name '*.pem' \
    -print \
    -quit | grep -q .
then
    echo "Error: no MSP signer certificate found."
    exit 1
fi

if [ ! -d "${MSP_DIR}/keystore" ]; then
    echo "Error: MSP keystore directory does not exist:"
    echo "  ${MSP_DIR}/keystore"
    exit 1
fi

if ! find "${MSP_DIR}/keystore" \
    -type f \
    -name '*_sk' \
    -print \
    -quit | grep -q .
then
    echo "Error: no MSP private key found."
    exit 1
fi

if [ ! -f "${MSP_DIR}/config.yaml" ]; then
    echo "Error: MSP config.yaml does not exist:"
    echo "  ${MSP_DIR}/config.yaml"
    exit 1
fi

# ============================================================
# Validate FABRIC-ENROLL-side TLS state
# ============================================================

if [ ! -d "${TLS_DIR}" ]; then
    echo "Error: TLS directory does not exist:"
    echo "  ${TLS_DIR}"
    exit 1
fi

for file in server.crt server.key ca.crt; do
    if [ ! -f "${TLS_DIR}/${file}" ]; then
        echo "Error: missing TLS file:"
        echo "  ${TLS_DIR}/${file}"
        exit 1
    fi
done

# ============================================================
# Prepare peer filesystem
# ============================================================

mkdir -p "${PRODUCTION_DIR}"

# ============================================================
# Generate peer configuration
# ============================================================

cat > "${CORE_CONFIG}" <<EOF
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

vm:
  endpoint: unix:///var/run/docker.sock

chaincode:
  mode: net

operations:
  listenAddress: 0.0.0.0:9443
  tls:
    enabled: false
EOF

echo "Peer configuration:"
echo "  ${CORE_CONFIG}"
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
# ============================================================

echo "Starting Fabric peer..."

docker run \
    -d \
    --name "${PEER_CONTAINER}" \
    --hostname "${PEER_HOSTNAME}" \
    --network "${XIT_NETWORK}" \
    --ip "${PEER_IP}" \
    -v "${HOST_PEER_STATE_DIR}:/etc/hyperledger/fabric:rw" \
    -v "${HOST_PEER_STATE_DIR}/production:/var/hyperledger/production:rw" \
    -v /var/run/docker.sock:/var/run/docker.sock \
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