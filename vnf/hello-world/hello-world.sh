#!/bin/sh

set -e

VNF_IP="${VNF_IP:?VNF_IP is not set}"
VNF_PORT="${VNF_PORT:-5000}"
VNF_PEERS="${VNF_PEERS:-}"

echo "=============================================="
echo " Hello World VNF"
echo "=============================================="
echo "XIT IP : ${VNF_IP}"
echo "Port   : ${VNF_PORT}"
echo "Peers  : ${VNF_PEERS:-none}"
echo "=============================================="
echo

# Listen for incoming VNF connections
(
    while true; do
        nc -l -p "$VNF_PORT" | while IFS= read -r message; do
            echo "[RECEIVED] ${message}"
        done
    done
) &

sleep 1

# Send a message to every configured VNF peer every 5 seconds
while true; do

    if [ -n "$VNF_PEERS" ]; then
        OLD_IFS="$IFS"
        IFS=','

        for PEER_IP in $VNF_PEERS; do
            echo "[SENDING] HELLO WORLD from ${VNF_IP} -> ${PEER_IP}"

            printf 'HELLO WORLD from %s\n' "$VNF_IP" | \
                nc "$PEER_IP" "$VNF_PORT" || true
        done

        IFS="$OLD_IFS"
    fi

    sleep 5
done