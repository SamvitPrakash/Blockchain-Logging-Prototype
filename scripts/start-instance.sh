#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

GNB_DIR="build/gnb-${INSTANCE}"
UE_DIR="build/ue-${INSTANCE}"

if [ ! -d "$GNB_DIR" ]; then
    echo "Error: gNB instance ${INSTANCE} does not exist."
    echo "Expected: ${GNB_DIR}"
    exit 1
fi

if [ ! -d "$UE_DIR" ]; then
    echo "Error: UE instance ${INSTANCE} does not exist."
    echo "Expected: ${UE_DIR}"
    exit 1
fi

echo "=============================================="
echo " Starting instance ${INSTANCE}"
echo "=============================================="

echo
echo "Starting gNB..."
docker compose -f "${GNB_DIR}/compose.yaml" up -d

echo
echo "Starting UE..."
docker compose -f "${UE_DIR}/compose.yaml" up -d

echo
echo "=============================================="
echo " Instance ${INSTANCE} started successfully"
echo "=============================================="

echo
echo "Containers:"
docker ps --filter "name=nr_gnb_${INSTANCE}" \
         --filter "name=nr_ue_${INSTANCE}" \
         --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"