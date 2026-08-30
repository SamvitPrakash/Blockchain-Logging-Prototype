docker rm -f fabric-bootstrap fabric-ca fabric-orderer-1 vnfm
docker rm -f fabric-enroll-1 fabric-peer-1
docker rm -f fabric-enroll-2 fabric-peer-2
docker rm -f fabric-enroll-3 fabric-peer-3
docker rm -f fabric-enroll-4 fabric-peer-4
docker rm -f fabric-enroll-5 fabric-peer-5
docker rm -f fabric-enroll-6 fabric-peer-6
docker rm -f fabric-enroll-7 fabric-peer-7
docker rm -f fabric-enroll-8 fabric-peer-8
docker rm -f fabric-enroll-9 fabric-peer-9
docker rm -f fabric-enroll-10 fabric-peer-10

rm -rf build/*

./scripts/fabric-ca/create.sh

./scripts/fabric-enroll/create-instance.sh 1
./scripts/fabric-enroll/create-instance.sh 2
./scripts/fabric-enroll/create-instance.sh 3
./scripts/fabric-enroll/create-instance.sh 4
./scripts/fabric-enroll/create-instance.sh 5
./scripts/fabric-enroll/create-instance.sh 6
./scripts/fabric-enroll/create-instance.sh 7
./scripts/fabric-enroll/create-instance.sh 8
./scripts/fabric-enroll/create-instance.sh 9
./scripts/fabric-enroll/create-instance.sh 10

./scripts/fabric-bootstrap/create.sh

docker compose -f build/fabric-ca/compose.yaml up -d

docker compose -f build/fabric-bootstrap/compose.yaml up -d

docker compose -f build/fabric-enroll-1/compose.yaml up -d
docker compose -f build/fabric-enroll-2/compose.yaml up -d
docker compose -f build/fabric-enroll-3/compose.yaml up -d
docker compose -f build/fabric-enroll-4/compose.yaml up -d
docker compose -f build/fabric-enroll-5/compose.yaml up -d
docker compose -f build/fabric-enroll-6/compose.yaml up -d
docker compose -f build/fabric-enroll-7/compose.yaml up -d
docker compose -f build/fabric-enroll-8/compose.yaml up -d
docker compose -f build/fabric-enroll-9/compose.yaml up -d
docker compose -f build/fabric-enroll-10/compose.yaml up -d

./scripts/fabric-network/create.sh 10 3 12345

# ./scripts/fabric-network/join-peers.sh

./scripts/vnfm/create.sh

docker compose -f build/vnfm/compose.yaml up -d
