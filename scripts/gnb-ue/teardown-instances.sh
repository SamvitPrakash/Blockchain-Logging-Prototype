#!/bin/bash

set -e

echo "=============================================="
echo " Tearing down all 5G instances"
echo "=============================================="

for compose_file in build/gnb-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    # docker compose -f "$compose_file" down
    docker rm -f "$compose_file"
done

for compose_file in build/ue-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    # docker compose -f "$compose_file" down
    docker rm -f "$compose_file"
done

echo
echo "=============================================="
echo " Stopping FABRIC-ENROLL instances"
echo "=============================================="

for compose_file in build/fabric-enroll-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    # docker compose -f "$compose_file" down
    docker rm -f "$compose_file"
done

echo
echo "=============================================="
echo " Removing OAM networks"
echo "=============================================="

for network in $(docker network ls --format '{{.Name}}' | grep '^OAM-[0-9]\+$' || true); do
    echo "Removing ${network}..."
    docker network rm "$network"
done

echo
echo "=============================================="
echo " Removing subscribers"
echo "=============================================="

docker exec mongo mongosh --quiet open5gs --eval \
'db.subscribers.deleteMany({})'

echo
echo "=============================================="
echo " Removing XIT network"
echo "=============================================="

if docker network inspect XIT >/dev/null 2>&1; then
    docker network rm XIT
else
    echo "XIT does not exist."
fi

echo
echo "=============================================="
echo " Teardown complete"
echo "=============================================="