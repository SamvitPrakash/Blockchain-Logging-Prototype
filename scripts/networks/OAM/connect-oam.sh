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

GNB_CONTAINER="nr_gnb_${INSTANCE}"
NETWORK_NAME="OAM-${INSTANCE}"
GNB_IP="10.20.${INSTANCE}.2"

echo "=============================================="
echo " Connecting gNB ${INSTANCE} to OAM"
echo "=============================================="
echo
echo "Container : ${GNB_CONTAINER}"
echo "Network   : ${NETWORK_NAME}"
echo "gNB IP    : ${GNB_IP}"
echo

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Error: OAM network '${NETWORK_NAME}' does not exist."
    echo
    echo "Create it first with:"
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    exit 1
fi

if ! docker inspect "$GNB_CONTAINER" >/dev/null 2>&1; then
    echo "Error: gNB container '${GNB_CONTAINER}' does not exist."
    exit 1
fi

if docker inspect "$GNB_CONTAINER" \
    --format '{{json .NetworkSettings.Networks}}' |
    grep -q "\"${NETWORK_NAME}\""; then

    echo "gNB is already connected to ${NETWORK_NAME}."
    exit 0
fi

docker network connect \
    --ip "$GNB_IP" \
    "$NETWORK_NAME" \
    "$GNB_CONTAINER"

echo
echo "=============================================="
echo " gNB ${INSTANCE} connected to OAM successfully"
echo "=============================================="