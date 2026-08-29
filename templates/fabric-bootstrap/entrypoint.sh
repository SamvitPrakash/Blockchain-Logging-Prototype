#!/bin/bash

set -e

echo "=============================================="
echo " FABRIC-BOOTSTRAP"
echo "=============================================="
echo
echo "FABRIC-BOOTSTRAP name    : ${VNFM_NAME}"
echo "XIT network  : ${XIT_NETWORK}"
echo "FABRIC-BOOTSTRAP IP      : ${VNFM_IP}"
echo "CA IP        : ${CA_IP}"
echo "Orderer IP   : ${ORDERER_IP}"
echo
echo "=============================================="
echo " Starting nested Fabric services"
echo "=============================================="
echo

/opt/fabric-bootstrap/start-ca.sh

echo "CA initialization complete."
echo

/opt/fabric-bootstrap/start-orderer.sh

echo "Orderer initialization complete."
echo

echo "=============================================="
echo " FABRIC-BOOTSTRAP startup complete"
echo "=============================================="
echo

exec sleep infinity