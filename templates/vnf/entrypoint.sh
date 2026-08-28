#!/bin/bash

set -e

echo "=============================================="
echo " VNF"
echo "=============================================="
echo
echo "VNF instance : ${VNF_INSTANCE}"
echo "VNF name     : ${VNF_NAME}"
echo "OAM network  : ${OAM_NETWORK}"
echo "OAM address  : ${OAM_IP}"
echo "XIT network  : ${XIT_NETWORK}"
echo "Peer address : ${PEER_IP}"
echo

exec sleep infinity