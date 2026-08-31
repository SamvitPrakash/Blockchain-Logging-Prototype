#!/bin/bash

set -euo pipefail

: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_HOSTNAME:?PEER_HOSTNAME is required}"
: "${PEER_STATE_DIR:?PEER_STATE_DIR is required}"

MSP_DIR="${PEER_STATE_DIR}/msp"
TLS_DIR="${PEER_STATE_DIR}/tls"
CORE_CONFIG="${PEER_STATE_DIR}/core.yaml"
PRODUCTION_DIR="${PEER_STATE_DIR}/production"

echo "=============================================="
echo " Preparing Fabric peer"
echo "=============================================="
echo
echo "Peer          : ${PEER_NAME}"
echo "Hostname      : ${PEER_HOSTNAME}"
echo "Peer state    : ${PEER_STATE_DIR}"
echo

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

mkdir -p "${PRODUCTION_DIR}"

cat > "${CORE_CONFIG}" <<YAML
peer:

  id: ${PEER_NAME}

  networkId: dev

  listenAddress: 0.0.0.0:7051

  chaincodeListenAddress: 0.0.0.0:7052

  chaincodeAddress: ${PEER_HOSTNAME}:7052

  address: ${PEER_HOSTNAME}:7051

  addressAutoDetect: false

  gossip:
    bootstrap: ${PEER_HOSTNAME}:7051
    externalEndpoint: ${PEER_HOSTNAME}:7051

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

  gateway:
    enabled: true

  discovery:
    enabled: true

vm:

  endpoint: unix:///var/run/docker.sock

  docker:
    tls:
      enabled: false

    attachStdout: false

chaincode:

  mode: net

  builder: hyperledger/fabric-ccenv:2.5

  pull: false

  golang:
    runtime: hyperledger/fabric-baseos:2.5

  system:
    _lifecycle: enable
    cscc: enable
    lscc: enable
    escc: enable
    vscc: enable
    qscc: enable

operations:

  listenAddress: 0.0.0.0:9443

  tls:
    enabled: false
YAML

echo
echo "Peer configuration generated:"
echo "  ${CORE_CONFIG}"
echo
echo "Docker chaincode builder:"
echo "  VM endpoint: unix:///var/run/docker.sock"
echo "  Builder:     hyperledger/fabric-ccenv:2.5"
echo
echo "=============================================="
echo " Fabric peer preparation complete"
echo "=============================================="