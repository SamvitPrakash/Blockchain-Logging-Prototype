#!/bin/bash

set -e

echo "=============================================="
echo " Fabric Orderer Bootstrap"
echo "=============================================="
echo

echo "Bootstrap : ${VNFM_NAME}"
echo "Bootstrap IP : ${VNFM_IP}"
echo "CA        : ${CA_IP}:7054"
echo "Orderer   : ${ORDERER_IP}"

echo
echo "=============================================="
echo " Enrolling Fabric orderer"
echo "=============================================="
echo

/opt/fabric-bootstrap/enroll-orderer.sh

echo
echo "=============================================="
echo " Fabric Orderer Bootstrap Complete"
echo "=============================================="
echo

exit 0