#!/bin/bash

docker rm -f vnf-1 vnfm fabric-ca

rm -rf build/*

./scripts/vnf/create-instance.sh 1

./scripts/vnfm/create.sh

docker compose -f build/vnf-1/compose.yaml up -d

docker compose -f build/vnfm/compose.yaml up -d

./build/vnfm/start-ca.sh
./build/vnfm/start-orderer.sh

./build/vnf-1/register-peer.sh
./build/vnf-1/enroll-peer.sh
./build/vnf-1/start-peer.sh