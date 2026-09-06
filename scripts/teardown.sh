#!/bin/bash

set -e

echo
echo "=============================================="
echo " Tearing down all VNF instances"
echo "=============================================="

for compose_file in build/vnf-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose --progress plain -f "$compose_file" down -v &
    
done

echo
echo "=============================================="
echo " Tearing down all FABRIC-ENROLL/FABRIC-PEER instances"
echo "=============================================="

for compose_file in build/fabric-enroll-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose --progress plain -f "$compose_file" down -v &
    
done

echo "=============================================="
echo " Tearing down all 5G instances"
echo "=============================================="

for compose_file in build/gnb-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose --progress plain -f "$compose_file" down -v &

done

for compose_file in build/ue-*/compose.yaml; do
    [ -e "$compose_file" ] || continue

    echo
    echo "Stopping $(dirname "$compose_file")..."
    docker compose --progress plain -f "$compose_file" down -v &
    
done

echo
echo "=============================================="
echo " Tearing down VNFM instance"
echo "=============================================="


docker compose --progress plain -f "build/vnfm/compose.yaml" down -v &

echo
echo "=============================================="
echo " Tearing down FABRIC-BOOTSTRAP/FABRIC-ORDERER instance"
echo "=============================================="

docker compose --progress plain -f "build/fabric-bootstrap/compose.yaml" down -v &

echo
echo "=============================================="
echo " Tearing down FABRIC-CA instance"
echo "=============================================="

docker compose --progress plain -f "build/fabric-ca/compose.yaml" down -v &

echo
echo "=============================================="
echo " Removing subscribers"
echo "=============================================="

docker exec mongo mongosh --quiet open5gs --eval \
'db.subscribers.deleteMany({})'

wait

echo
echo "=============================================="
echo " Tearing down all FABRIC-LOGGING instances"
echo "=============================================="

docker rm -f  $(docker ps -aq --filter "name=dev-fabric-peer-") &

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
echo " Removing XIT network"
echo "=============================================="

if docker network inspect XIT >/dev/null 2>&1; then
    docker network rm XIT
else
    echo "XIT does not exist."
fi

echo
echo "=============================================="
echo " Removing gNB log volumes"
echo "=============================================="

for volume in $(docker volume ls --format '{{.Name}}' | grep '^gnb-[0-9]\+-logs$' || true); do
    echo "Removing ${volume}..."
    docker volume rm "$volume"
done

echo
echo "=============================================="
echo " Teardown complete"
echo "=============================================="