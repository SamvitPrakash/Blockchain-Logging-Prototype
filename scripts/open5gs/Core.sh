#!/bin/bash

cd docker_open5gs/
source .env
docker compose -f sa-deploy.yaml up -d
cd ../