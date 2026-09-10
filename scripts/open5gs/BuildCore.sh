#!/bin/bash

cd docker_open5gs/base
docker build --no-cache --force-rm -t docker_open5gs .
cd ../../