#!/bin/bash

MARKER="scripts/.init"

if [ -f "$MARKER" ]; then
    exit 0
fi

echo
echo "################################################"
echo "Running initialization..."
echo "################################################"

./scripts/open5gs/Core.sh

touch "$MARKER"

exit 0