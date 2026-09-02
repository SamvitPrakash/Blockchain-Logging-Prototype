#!/bin/bash

set -e

# ============================================================
# Validate arguments
# ============================================================

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GNB_DIR="$PROJECT_ROOT/build/gnb-${INSTANCE}"
UE_DIR="$PROJECT_ROOT/build/ue-${INSTANCE}"

OAM_CREATE_SCRIPT="$PROJECT_ROOT/scripts/networks/OAM/create-oam-network.sh"
OAM_CONNECT_SCRIPT="$PROJECT_ROOT/scripts/networks/OAM/connect-oam.sh"

GNB_CONTAINER="nr_gnb_${INSTANCE}"
UE_CONTAINER="nr_ue_${INSTANCE}"

OPEN5GS_NETWORK="docker_open5gs_default"

# ============================================================
# Validate instance
# ============================================================

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

# ============================================================
# Validate OAM scripts
# ============================================================

if [ ! -x "$OAM_CREATE_SCRIPT" ]; then
    echo "Error: OAM creation script not found or not executable:"
    echo "  $OAM_CREATE_SCRIPT"
    exit 1
fi

if [ ! -x "$OAM_CONNECT_SCRIPT" ]; then
    echo "Error: OAM connection script not found or not executable:"
    echo "  $OAM_CONNECT_SCRIPT"
    exit 1
fi

# ============================================================
# Start instance
# ============================================================

echo "=============================================="
echo " Starting instance ${INSTANCE}"
echo "=============================================="
echo

# ============================================================
# Validate Open5GS network
# ============================================================

echo "Checking Open5GS network..."

if ! docker network inspect "$OPEN5GS_NETWORK" >/dev/null 2>&1; then
    echo
    echo "Error: required Docker network does not exist:"
    echo "  ${OPEN5GS_NETWORK}"
    echo
    echo "The Open5GS stack must be running before starting"
    echo "gNB/UE instances."
    exit 1
fi

echo "Open5GS network exists."

# ============================================================
# OAM network
# ============================================================

echo
echo "Checking OAM network..."

if docker network inspect "OAM-${INSTANCE}" >/dev/null 2>&1; then
    echo "OAM-${INSTANCE} already exists."
else
    echo "Creating OAM network..."
    "$OAM_CREATE_SCRIPT" "$INSTANCE"
fi

# ============================================================
# Remove stale gNB container
# ============================================================

echo
echo "Checking gNB container..."

if docker inspect "$GNB_CONTAINER" >/dev/null 2>&1; then
    echo "Existing container found: ${GNB_CONTAINER}"
    echo "Removing existing gNB container..."

    docker rm -f "$GNB_CONTAINER" >/dev/null

    echo "Removed stale gNB container."
fi

# ============================================================
# Start gNB
# ============================================================

echo
echo "Starting gNB..."

docker compose \
    -f "$GNB_DIR/compose.yaml" \
    up -d

# ============================================================
# Verify gNB is running
# ============================================================

echo
echo "Verifying gNB..."

if ! docker inspect "$GNB_CONTAINER" >/dev/null 2>&1; then
    echo "Error: gNB container was not created:"
    echo "  ${GNB_CONTAINER}"
    exit 1
fi

GNB_STATUS="$(docker inspect \
    --format '{{.State.Status}}' \
    "$GNB_CONTAINER")"

if [ "$GNB_STATUS" != "running" ]; then
    echo "Error: gNB container is not running."
    echo "Status: ${GNB_STATUS}"
    exit 1
fi

echo "gNB is running."

# ============================================================
# Connect gNB to OAM
# ============================================================

echo
echo "Connecting gNB to OAM..."

"$OAM_CONNECT_SCRIPT" "$INSTANCE"

# ============================================================
# Remove stale UE container
# ============================================================

echo
echo "Checking UE container..."

if docker inspect "$UE_CONTAINER" >/dev/null 2>&1; then
    echo "Existing container found: ${UE_CONTAINER}"
    echo "Removing existing UE container..."

    docker rm -f "$UE_CONTAINER" >/dev/null

    echo "Removed stale UE container."
fi

# ============================================================
# Start UE
# ============================================================

echo
echo "Starting UE..."

docker compose \
    -f "$UE_DIR/compose.yaml" \
    up -d

# ============================================================
# Verify UE is running
# ============================================================

echo
echo "Verifying UE..."

if ! docker inspect "$UE_CONTAINER" >/dev/null 2>&1; then
    echo "Error: UE container was not created:"
    echo "  ${UE_CONTAINER}"
    exit 1
fi

UE_STATUS="$(docker inspect \
    --format '{{.State.Status}}' \
    "$UE_CONTAINER")"

if [ "$UE_STATUS" != "running" ]; then
    echo "Error: UE container is not running."
    echo "Status: ${UE_STATUS}"
    exit 1
fi

echo "UE is running."

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " Instance ${INSTANCE} started successfully"
echo "=============================================="
echo

echo "Containers:"
docker ps \
    --filter "name=nr_gnb_${INSTANCE}" \
    --filter "name=nr_ue_${INSTANCE}" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"