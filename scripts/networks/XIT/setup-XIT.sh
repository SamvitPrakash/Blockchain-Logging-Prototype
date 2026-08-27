#!/bin/bash

set -e

NETWORK_NAME="XIT"
SUBNET="10.10.0.0/24"

echo "=============================================="
echo " Setting up XIT network"
echo "=============================================="

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Network '$NETWORK_NAME' already exists."
else
    docker network create \
        --driver bridge \
        --subnet "$SUBNET" \
        "$NETWORK_NAME"

    echo "Network '$NETWORK_NAME' created."
fi

echo
echo "=============================================="
echo " XIT network ready"
echo "=============================================="