#!/bin/bash

set -euo pipefail

echo
echo "=============================================="
echo " Starting VNFM"
echo "=============================================="
echo

: "${VNFM_MSP_ID:?VNFM_MSP_ID is required}"
: "${VNFM_MSPCONFIGPATH:?VNFM_MSPCONFIGPATH is required}"
: "${VNFM_TOPOLOGY_FILE:?VNFM_TOPOLOGY_FILE is required}"
: "${VNFM_TLS_CA:?VNFM_TLS_CA is required}"
: "${VNFM_TLS_CLIENT_CERT:?VNFM_TLS_CLIENT_CERT is required}"
: "${VNFM_TLS_CLIENT_KEY:?VNFM_TLS_CLIENT_KEY is required}"
: "${VNFM_ORDERER_ENDPOINT:?VNFM_ORDERER_ENDPOINT is required}"

if [ ! -d "$VNFM_MSPCONFIGPATH" ]; then
    echo "ERROR: VNFM admin MSP does not exist:"
    echo "  $VNFM_MSPCONFIGPATH"
    exit 1
fi

if [ ! -f "$VNFM_MSPCONFIGPATH/signcerts/cert.pem" ]; then
    echo "ERROR: VNFM admin certificate does not exist."
    exit 1
fi

if [ ! -f "$VNFM_MSPCONFIGPATH/config.yaml" ]; then
    echo "ERROR: VNFM admin MSP config.yaml does not exist."
    exit 1
fi

if [ ! -f "$VNFM_TOPOLOGY_FILE" ]; then
    echo "ERROR: topology does not exist:"
    echo "  $VNFM_TOPOLOGY_FILE"
    exit 1
fi

if [ ! -f "$VNFM_TLS_CA" ]; then
    echo "ERROR: TLS CA does not exist:"
    echo "  $VNFM_TLS_CA"
    exit 1
fi

if [ ! -f "$VNFM_TLS_CLIENT_CERT" ]; then
    echo "ERROR: TLS client certificate does not exist:"
    echo "  $VNFM_TLS_CLIENT_CERT"
    exit 1
fi

if [ ! -f "$VNFM_TLS_CLIENT_KEY" ]; then
    echo "ERROR: TLS client key does not exist:"
    echo "  $VNFM_TLS_CLIENT_KEY"
    exit 1
fi

echo "VNFM configuration:"
echo "  MSP ID       : ${VNFM_MSP_ID}"
echo "  MSP           : ${VNFM_MSPCONFIGPATH}"
echo "  Topology      : ${VNFM_TOPOLOGY_FILE}"
echo "  Orderer       : ${VNFM_ORDERER_ENDPOINT}"

echo
echo "=============================================="
echo " Joining orderer to channels"
echo "=============================================="
echo

/opt/vnfm/join-orderer.sh

echo
echo "=============================================="
echo " Deploying logging chaincode"
echo "=============================================="
echo

/opt/vnfm/manage-chaincode.sh

echo
echo "=============================================="
echo " VNFM READY"
echo "=============================================="
echo

exec tail -f /dev/null