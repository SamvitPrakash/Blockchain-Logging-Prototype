#!/bin/bash

set -e

echo "=============================================="
echo " Tearing down all 5G instances"
echo "=============================================="

for compose_file in build/gnb-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose -f "$compose_file" down
done

for compose_file in build/ue-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose -f "$compose_file" down
done

echo
echo "Removing all Open5GS subscribers..."
docker exec mongo mongosh --quiet open5gs --eval \
'db.subscribers.deleteMany({})'

echo
echo "=============================================="
echo " All generated instances have been removed"
echo "=============================================="