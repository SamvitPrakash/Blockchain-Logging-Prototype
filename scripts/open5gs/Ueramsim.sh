#!/bin/bash

cd docker_open5gs/
docker compose -f nr-ue.yaml up -d
cd ../