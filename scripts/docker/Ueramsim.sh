#!/bin/bash

cd docker_open5gs/
docker compose -f nr-ue.yaml up -d && docker container attach nr_ue
cd ../