#!/bin/bash

set -e

NETWORK_NAME="XIT"
SUBNET="10.10.0.0/24"
GATEWAY="10.10.0.1"

echo "=============================================="
echo " Setting up XIT network"
echo "=============================================="
echo
echo "Network : ${NETWORK_NAME}"
echo "Subnet  : ${SUBNET}"
echo "Gateway : ${GATEWAY}"
echo

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Network '${NETWORK_NAME}' already exists."

    EXISTING_SUBNET=$(docker network inspect \
        --format '{{(index .IPAM.Config 0).Subnet}}' \
        "$NETWORK_NAME")

    if [ "$EXISTING_SUBNET" != "$SUBNET" ]; then
        echo "Error: existing XIT network has subnet ${EXISTING_SUBNET}."
        echo "Expected: ${SUBNET}"
        exit 1
    fi
else
    docker network create \
        --driver bridge \
        --subnet "$SUBNET" \
        --gateway "$GATEWAY" \
        "$NETWORK_NAME"

    echo "Network '${NETWORK_NAME}' created."
fi

echo
echo "=============================================="
echo " XIT address allocation"
echo "=============================================="
echo
echo "Gateway       : ${GATEWAY}"
echo "VNFM          : 10.10.0.10"
echo "CA            : 10.10.0.11"
echo "Orderer base  : 10.10.0.20"
echo "Peer base     : 10.10.0.100"
echo

echo "=============================================="
echo " XIT network ready"
echo "=============================================="