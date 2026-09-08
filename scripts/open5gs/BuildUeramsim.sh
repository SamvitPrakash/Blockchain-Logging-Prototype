#!/bin/bash

cd docker_open5gs/ueransim
docker build --no-cache --force-rm -t docker_ueransim .
cd ../../