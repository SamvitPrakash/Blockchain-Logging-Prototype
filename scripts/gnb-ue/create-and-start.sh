#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <number-of-instances>"
    exit 1
fi

for ((i=1; i<=$1; i++)); do
    ./scripts/create-instance.sh "$i"
done

for ((i=1; i<=$1; i++)); do
    ./scripts/start-instance.sh "$i"
done