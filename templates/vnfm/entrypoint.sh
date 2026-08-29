#!/bin/bash

set -e

echo "=============================================="
echo " VNFM"
echo "=============================================="
echo
echo "VNFM name    : ${VNFM_NAME}"
echo "XIT network  : ${XIT_NETWORK}"
echo "VNFM IP      : ${VNFM_IP}"
echo "CA IP        : ${CA_IP}"
echo "Orderer IP   : ${ORDERER_IP}"
echo
echo "=============================================="
echo " Starting nested Fabric services"
echo "=============================================="
echo

/opt/vnfm/start-ca.sh

echo "CA initialization complete."
echo

/opt/vnfm/start-orderer.sh

echo "Orderer initialization complete."
echo

echo "=============================================="
echo " VNFM startup complete"
echo "=============================================="
echo

exec sleep infinity