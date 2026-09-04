#!/bin/bash

set -e

TOWER_COUNT="${1:-}"
LEDGER_COUNT="${2:-}"
GENERATION_SEED="${3:-}"

if [ -z "$TOWER_COUNT" ] || [ -z "$LEDGER_COUNT" ] || [ -z "$GENERATION_SEED" ]; then
  echo "Usage: $0 <tower_count> <ledger_count> <generation_seed> [verbose]"
  exit 1
fi

./scripts/init.sh

echo
echo "########################################################################"
echo "Cleaning up old generated files..."
echo "########################################################################"

./scripts/teardown.sh
./scripts/clean.sh

echo
echo "########################################################################"
echo "Creating XIT network..."
echo "########################################################################"

./scripts/networks/XIT/setup-XIT.sh

echo
echo "########################################################################"
echo "Generating $TOWER_COUNT towers"
echo "########################################################################"

./scripts/gnb-ue/create-and-start.sh "$TOWER_COUNT"

echo
echo "########################################################################"
echo "Generating FABRIC-CA"
echo "########################################################################"

./scripts/fabric-ca/create.sh

echo 
echo "########################################################################"
echo "Generating FABRIC-BOOTSTRAP"
echo "########################################################################"

./scripts/fabric-bootstrap/create.sh

echo 
echo "########################################################################"
echo "Generating FABRIC-ENROLL instances"
echo "########################################################################"

for i in $(seq 1 "$TOWER_COUNT"); do
  ./scripts/fabric-enroll/create-instance.sh "$i"
done

echo 
echo "########################################################################"
echo "Starting FABRIC-CA, FABRIC-BOOTSTRAP, and FABRIC-ENROLL instances"
echo "########################################################################"

docker compose -f build/fabric-ca/compose.yaml up -d
docker compose -f build/fabric-bootstrap/compose.yaml up -d

for i in $(seq 1 "$TOWER_COUNT"); do
  docker compose -f "build/fabric-enroll-$i/compose.yaml" up -d
done

echo
echo "########################################################################"
echo "Generating FABRIC-NETWORK"
echo "########################################################################"

./scripts/fabric-network/create.sh "$TOWER_COUNT" "$LEDGER_COUNT" "$GENERATION_SEED"
./scripts/fabric-network/join-peers.sh

echo
echo "########################################################################"
echo "Generating VNFM"
echo "########################################################################"

./scripts/vnfm/create.sh

echo
echo "########################################################################"
echo "Generating VNF instances"
echo "########################################################################"

for i in $(seq 1 "$TOWER_COUNT"); do
  ./scripts/vnf/create.sh "$i"
done

echo
echo "########################################################################"
echo "Starting VNFM and VNF instances"
echo "########################################################################"

docker compose -f build/vnfm/compose.yaml up -d

for i in $(seq 1 "$TOWER_COUNT"); do
  docker compose -f "build/vnf-$i/compose.yaml" up -d --build
done

echo
echo "########################################################################"
echo "All components have been generated and started successfully."
echo "########################################################################"