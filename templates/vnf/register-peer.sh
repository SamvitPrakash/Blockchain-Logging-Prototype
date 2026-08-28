#!/bin/bash

set -e

: "${PEER_NAME:?PEER_NAME is required}"
: "${PEER_SECRET:?PEER_SECRET is required}"
: "${CA_IP:?CA_IP is required}"
: "${XIT_NETWORK:?XIT_NETWORK is required}"

CA_CONTAINER="fabric-ca"
CLIENT_IMAGE="hyperledger/fabric-ca:1.5.17"
CLIENT_HOME="/tmp/fabric-ca-client-${PEER_NAME}"

echo "=============================================="
echo " Registering Fabric peer"
echo "=============================================="
echo
echo "Peer       : ${PEER_NAME}"
echo "CA         : ${CA_CONTAINER}"
echo "CA IP      : ${CA_IP}"
echo "XIT        : ${XIT_NETWORK}"
echo

docker run --rm \
    --network "${XIT_NETWORK}" \
    --name "fabric-ca-client-${PEER_NAME}" \
    -e FABRIC_CA_CLIENT_HOME="${CLIENT_HOME}" \
    "${CLIENT_IMAGE}" \
    sh -c "
        set -e

        mkdir -p '${CLIENT_HOME}'

        echo 'Enrolling CA administrator...'

        fabric-ca-client enroll \
            -u http://admin:adminpw@${CA_IP}:7054 \
            --home '${CLIENT_HOME}'

        echo 'Registering peer...'

        fabric-ca-client register \
            --home '${CLIENT_HOME}' \
            --id.name '${PEER_NAME}' \
            --id.secret '${PEER_SECRET}' \
            --id.type peer \
            --id.affiliation 'org1.peer' \
            -u http://${CA_IP}:7054
    "

echo
echo "Peer '${PEER_NAME}' registered successfully."
