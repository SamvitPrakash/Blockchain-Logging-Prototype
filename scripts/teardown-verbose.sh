#!/bin/bash

set -e

echo
echo "=============================================="
echo " VERBOSE DOCKER TEARDOWN"
echo "=============================================="

echo
echo "=============================================="
echo " Stopping project containers"
echo "=============================================="

# Stop all currently running containers.
docker ps -q | xargs -r docker stop

echo
echo "=============================================="
echo " Removing all containers"
echo "=============================================="

docker ps -aq | xargs -r docker rm -f

echo
echo "=============================================="
echo " Removing all Docker volumes"
echo "=============================================="

docker volume ls -q | xargs -r docker volume rm -f

echo
echo "=============================================="
echo " Removing all Docker networks"
echo "=============================================="

# Do not try to remove Docker's built-in networks.
for network in $(docker network ls --format '{{.Name}}'); do
    case "$network" in
        bridge|host|none)
            ;;
        *)
            docker network rm "$network" 2>/dev/null || true
            ;;
    esac
done

echo
echo "=============================================="
echo " Removing all Docker images"
echo "=============================================="

docker image ls -aq | sort -u | xargs -r docker rmi -f

echo
echo "=============================================="
echo " Removing BuildKit cache"
echo "=============================================="

docker builder prune -af

echo
echo "=============================================="
echo " Removing generated experiment state"
echo "=============================================="

rm -rf build/*
rm -f scripts/.init

echo
echo "=============================================="
echo " Docker cleanup complete"
echo "=============================================="

echo
echo "Remaining Docker resources:"
echo

docker system df