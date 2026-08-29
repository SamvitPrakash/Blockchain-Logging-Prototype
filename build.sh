docker rm -f vnf-1 vnfm fabric-ca fabric-orderer-1

rm -rf build/*

./scripts/vnf/create-instance.sh 1

./scripts/vnfm/create.sh

docker compose -f build/vnfm/compose.yaml up -d
# ./run-vnfm.sh

docker compose -f build/vnf-1/compose.yaml up -d
