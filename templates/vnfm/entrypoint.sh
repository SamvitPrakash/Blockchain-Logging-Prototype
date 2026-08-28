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

exec sleep infinity