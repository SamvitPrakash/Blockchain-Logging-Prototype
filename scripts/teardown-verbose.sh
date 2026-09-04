#!/bin/bash

./scripts/teardown.sh
docker stop $(docker ps -q)
rm -f scripts/.init