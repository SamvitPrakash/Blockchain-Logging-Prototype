#!/bin/bash

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

NETWORK_NAME="OAM-${INSTANCE}"
SUBNET="10.20.${INSTANCE}.0/29"

echo "=============================================="
echo " Creating OAM network"
echo "=============================================="
echo
echo "Network : ${NETWORK_NAME}"
echo "Subnet  : ${SUBNET}"
echo

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Error: OAM network '${NETWORK_NAME}' already exists."
    exit 1
fi

docker network create \
    --driver bridge \
    --subnet "$SUBNET" \
    "$NETWORK_NAME"

echo
echo "=============================================="
echo " OAM network created successfully"
echo "=============================================="
echo
echo "Network : ${NETWORK_NAME}"
echo "Subnet  : ${SUBNET}"
echo "gNB IP  : 10.20.${INSTANCE}.2"
echo "VNF IP  : 10.20.${INSTANCE}.3"