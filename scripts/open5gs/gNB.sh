#!/bin/bash

cd docker_open5gs/
docker compose -f nr-gnb.yaml up -d && docker container attach nr_gnb
cd ../