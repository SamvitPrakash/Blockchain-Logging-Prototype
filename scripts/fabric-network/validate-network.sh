#!/bin/bash

for i in $(seq 1 10); do
    printf "fabric-peer-%-2s: " "$i"
    docker exec fabric-peer-${i} peer channel list 2>/dev/null |
        grep -E '^channel-' |
        tr '\n' ' '
    echo
done