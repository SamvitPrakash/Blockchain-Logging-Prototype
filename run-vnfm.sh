#!/bin/bash

./build/fabric-bootstrap/start-ca.sh
./build/fabric-bootstrap/start-orderer.sh

# ./build/fabric-enroll-1/register-peer.sh
# ./build/fabric-enroll-1/enroll-peer.sh
# ./build/fabric-enroll-1/start-peer.sh