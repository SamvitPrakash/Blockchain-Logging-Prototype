#!/bin/bash

set -e

echo "=============================================="
echo " FABRIC-BOOTSTRAP"
echo "=============================================="
echo

echo "FABRIC-BOOTSTRAP name : ${VNFM_NAME}"
echo "XIT network           : ${XIT_NETWORK}"
echo "FABRIC-BOOTSTRAP IP   : ${VNFM_IP}"
echo "CA IP                 : ${CA_IP}"
echo "Orderer IP            : ${ORDERER_IP}"

echo
echo "=============================================="
echo " Initializing Fabric orderer identity"
echo "=============================================="
echo

/opt/fabric-bootstrap/enroll-orderer.sh

echo
echo "=============================================="
echo " FABRIC-BOOTSTRAP complete"
echo "=============================================="
echo

exit 0