docker rm -f vnf-1
rm -rf build/vnf-1


./scripts/vnf/create.sh 1

docker compose -f build/vnf-1/compose.yaml up -d