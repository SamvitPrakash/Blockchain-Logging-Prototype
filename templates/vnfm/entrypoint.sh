#!/bin/bash

set -e

# ============================================================
# VNFM
# ============================================================

echo
echo "=============================================="
echo " VNFM"
echo "=============================================="
echo

echo "VNFM:"
echo "  Name: ${VNFM_NAME:-vnfm}"

echo
echo "Topology:"
echo "  ${VNFM_TOPOLOGY_FILE:-/opt/vnfm/topology.json}"

echo
echo "Orderer:"
echo "  ${VNFM_ORDERER_NAME:-fabric-orderer-1}"
echo "  Admin: ${VNFM_ORDERER_ADMIN_ENDPOINT:-fabric-orderer-1:9443}"

echo
echo "=============================================="
echo

if [ ! -f "${VNFM_TOPOLOGY_FILE:-/opt/vnfm/topology.json}" ]; then
    echo "ERROR: topology.json does not exist:"
    echo "  ${VNFM_TOPOLOGY_FILE:-/opt/vnfm/topology.json}"
    exit 1
fi

if [ ! -f "${VNFM_TLS_CA}" ]; then
    echo "ERROR: TLS CA does not exist:"
    echo "  ${VNFM_TLS_CA}"
    exit 1
fi

if [ ! -f "${VNFM_TLS_CLIENT_CERT}" ]; then
    echo "ERROR: TLS client certificate does not exist:"
    echo "  ${VNFM_TLS_CLIENT_CERT}"
    exit 1
fi

if [ ! -f "${VNFM_TLS_CLIENT_KEY}" ]; then
    echo "ERROR: TLS client key does not exist:"
    echo "  ${VNFM_TLS_CLIENT_KEY}"
    exit 1
fi

echo "VNFM prerequisites:"
echo "  OK"
echo

exec /opt/vnfm/join-orderer.sh