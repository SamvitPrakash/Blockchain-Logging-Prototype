docker rm -f fabric-enroll-1 fabric-bootstrap fabric-ca fabric-orderer-1 fabric-peer-1

rm -rf build/*

./scripts/fabric-ca/create.sh

./scripts/fabric-enroll/create-instance.sh 1

./scripts/fabric-bootstrap/create.sh

docker compose -f build/fabric-ca/compose.yaml up -d

docker compose -f build/fabric-bootstrap/compose.yaml up -d

docker compose -f build/fabric-enroll-1/compose.yaml up -d
