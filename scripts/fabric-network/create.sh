#!/bin/bash

set -euo pipefail

# ============================================================
# FABRIC-NETWORK Generator
#
# Generates:
#   1. Deterministic peer -> channel assignments
#   2. Fabric configtx.yaml
#   3. Fabric channel blocks
#
# Fabric tooling runs inside:
#   hyperledger/fabric-tools:2.5.16
#
# Architecture:
#   - ONE Fabric orderer
#   - Every peer belongs to exactly ONE channel
#   - Every channel contains >= 2 peers
#   - Channel sizes differ by at most one peer
#   - Peer assignment is deterministic for a given seed
#
# Usage:
#   ./scripts/fabric-network/create.sh <peers> <ledgers> [seed]
#
# Example:
#   ./scripts/fabric-network/create.sh 10 3 12345
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

BUILD_DIR="$PROJECT_ROOT/build/fabric-network"
CHANNEL_DIR="$BUILD_DIR/channels"

DEFAULT_SEED="12345"

FABRIC_TOOLS_IMAGE="${FABRIC_TOOLS_IMAGE:-hyperledger/fabric-tools:2.5.16}"

# Container-side project path.
CONTAINER_PROJECT_ROOT="/fabric-project"

CONTAINER_BUILD_DIR="${CONTAINER_PROJECT_ROOT}/build/fabric-network"

# ============================================================
# Arguments
# ============================================================

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage:"
    echo "  $0 <number-of-peers> <number-of-ledgers> [seed]"
    echo
    echo "Example:"
    echo "  $0 10 3 12345"
    exit 1
fi

PEER_COUNT="$1"
LEDGER_COUNT="$2"
SEED="${3:-$DEFAULT_SEED}"

# ============================================================
# Validation
# ============================================================

if ! [[ "$PEER_COUNT" =~ ^[0-9]+$ ]] || [ "$PEER_COUNT" -lt 2 ]; then
    echo "Error: number of peers must be an integer >= 2."
    exit 1
fi

if ! [[ "$LEDGER_COUNT" =~ ^[0-9]+$ ]] || [ "$LEDGER_COUNT" -lt 1 ]; then
    echo "Error: number of ledgers must be an integer >= 1."
    exit 1
fi

if ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: seed must be a non-negative integer."
    exit 1
fi

MAX_LEDGER_COUNT=$((PEER_COUNT / 2))

if [ "$LEDGER_COUNT" -gt "$MAX_LEDGER_COUNT" ]; then
    echo "Error: ${LEDGER_COUNT} ledgers cannot be created from ${PEER_COUNT} peers."
    echo
    echo "Each ledger must contain at least two unique peers."
    echo "Maximum valid ledger count: ${MAX_LEDGER_COUNT}"
    exit 1
fi

# ============================================================
# Docker
# ============================================================

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command was not found."
    exit 1
fi

echo
echo "Fabric tooling:"
echo "  ${FABRIC_TOOLS_IMAGE}"
echo

if ! docker image inspect "$FABRIC_TOOLS_IMAGE" >/dev/null 2>&1; then
    echo "Fabric tools image is not present locally."
    echo
    echo "Pulling:"
    echo "  ${FABRIC_TOOLS_IMAGE}"
    echo

    docker pull "$FABRIC_TOOLS_IMAGE"
fi

# ============================================================
# Existing Fabric identity material
# ============================================================

ORDERER_MSP_DIR="$PROJECT_ROOT/build/fabric-bootstrap/orderer/msp"
ORDERER_TLS_DIR="$PROJECT_ROOT/build/fabric-bootstrap/orderer/tls"
REFERENCE_PEER_MSP_DIR="$PROJECT_ROOT/build/fabric-enroll-1/peer/msp"

if [ ! -d "$ORDERER_MSP_DIR" ]; then
    echo "Error: orderer MSP does not exist:"
    echo "  $ORDERER_MSP_DIR"
    echo
    echo "Run the existing Fabric orderer bootstrap first."
    exit 1
fi

if [ ! -d "$ORDERER_TLS_DIR" ]; then
    echo "Error: orderer TLS directory does not exist:"
    echo "  $ORDERER_TLS_DIR"
    echo
    echo "Run the existing Fabric orderer bootstrap first."
    exit 1
fi

if [ ! -d "$REFERENCE_PEER_MSP_DIR" ]; then
    echo "Error: peer-1 MSP does not exist:"
    echo "  $REFERENCE_PEER_MSP_DIR"
    echo
    echo "Run the existing peer enrollment first."
    exit 1
fi

# ============================================================
# Clean build directory
# ============================================================

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    echo
    echo "Remove it before regenerating:"
    echo
    echo "  rm -rf ${BUILD_DIR}"
    echo
    exit 1
fi

mkdir -p "$CHANNEL_DIR"

# ============================================================
# Generate deterministic topology
# ============================================================

TOPOLOGY_FILE="$BUILD_DIR/topology.json"

python3 - "$PEER_COUNT" "$LEDGER_COUNT" "$SEED" "$TOPOLOGY_FILE" <<'PY'
import json
import random
import sys
from pathlib import Path

peer_count = int(sys.argv[1])
ledger_count = int(sys.argv[2])
seed = int(sys.argv[3])
output_file = Path(sys.argv[4])

# ------------------------------------------------------------
# Balanced channel sizes.
#
# Example:
#   10 peers / 3 channels
#   -> 4, 3, 3
# ------------------------------------------------------------

base_size = peer_count // ledger_count
remainder = peer_count % ledger_count

ledger_sizes = [
    base_size + (1 if ledger_index < remainder else 0)
    for ledger_index in range(ledger_count)
]

# ------------------------------------------------------------
# Deterministic pseudorandom assignment.
# ------------------------------------------------------------

rng = random.Random(seed)

peers = [
    f"fabric-peer-{peer_number}"
    for peer_number in range(1, peer_count + 1)
]

rng.shuffle(peers)

# ------------------------------------------------------------
# Assign every peer exactly once.
# ------------------------------------------------------------

assignments = {}

offset = 0

for ledger_index, ledger_size in enumerate(ledger_sizes, start=1):

    channel_name = f"channel-{ledger_index}"

    assignments[channel_name] = peers[
        offset:offset + ledger_size
    ]

    offset += ledger_size

# ------------------------------------------------------------
# Defensive validation.
# ------------------------------------------------------------

assigned = [
    peer
    for channel_peers in assignments.values()
    for peer in channel_peers
]

if len(assigned) != peer_count:
    raise RuntimeError(
        f"Assignment contains {len(assigned)} peers; "
        f"expected {peer_count}."
    )

if len(set(assigned)) != peer_count:
    raise RuntimeError(
        "A peer was assigned to more than one channel."
    )

if any(len(channel_peers) < 2 for channel_peers in assignments.values()):
    raise RuntimeError(
        "Every channel must contain at least two peers."
    )

sizes = [
    len(channel_peers)
    for channel_peers in assignments.values()
]

if max(sizes) - min(sizes) > 1:
    raise RuntimeError(
        "Channel assignments are not balanced."
    )

# ------------------------------------------------------------
# Reverse lookup.
# ------------------------------------------------------------

peer_to_channel = {}

for channel_name, channel_peers in assignments.items():

    for peer_name in channel_peers:
        peer_to_channel[peer_name] = channel_name

# ------------------------------------------------------------
# Topology manifest.
# ------------------------------------------------------------

topology = {
    "version": 1,

    "fabric": {
        "orderer": "fabric-orderer-1",
        "orderer_count": 1,
        "orderer_msp": "OrdererMSP"
    },

    "organization": {
        "name": "Org1",
        "msp_id": "Org1MSP"
    },

    "experiment": {
        "peer_count": peer_count,
        "ledger_count": ledger_count,
        "seed": seed
    },

    "ledger_sizes": ledger_sizes,

    "channels": assignments,

    "peer_to_channel": peer_to_channel
}

output_file.write_text(
    json.dumps(topology, indent=2) + "\n",
    encoding="utf-8"
)
PY

# ============================================================
# Generate configtx.yaml
# ============================================================

CONFIGTX_FILE="$BUILD_DIR/configtx.yaml"

cat > "$CONFIGTX_FILE" <<EOF
---
Organizations:

  - &OrdererOrg

    Name: OrdererMSP

    ID: OrdererMSP

    MSPDir: ${CONTAINER_PROJECT_ROOT}/build/fabric-bootstrap/orderer/msp

    Policies:

      Readers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"

      Writers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"

      Admins:
        Type: Signature
        Rule: "OR('OrdererMSP.admin')"


  - &Org1

    Name: Org1MSP

    ID: Org1MSP

    MSPDir: ${CONTAINER_PROJECT_ROOT}/build/fabric-enroll-1/peer/msp

    Policies:

      Readers:
        Type: Signature
        Rule: "OR('Org1MSP.member')"

      Writers:
        Type: Signature
        Rule: "OR('Org1MSP.member')"

      Admins:
        Type: Signature
        Rule: "OR('Org1MSP.admin')"

      Endorsement:
        Type: Signature
        Rule: "OR('Org1MSP.peer')"


Capabilities:

  Channel: &ChannelCapabilities
    V2_0: true

  Orderer: &OrdererCapabilities
    V2_0: true

  Application: &ApplicationCapabilities
    V2_5: true


Application: &ApplicationDefaults

  Organizations:

  Policies:

    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"

    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"

    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"

    LifecycleEndorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"

    Endorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"

  Capabilities:
    <<: *ApplicationCapabilities


Orderer: &OrdererDefaults

  OrdererType: etcdraft

  Addresses:
    - fabric-orderer-1:7050

  EtcdRaft:

    Consenters:

      - Host: fabric-orderer-1
        Port: 7050
        ClientTLSCert: ${CONTAINER_PROJECT_ROOT}/build/fabric-bootstrap/orderer/tls/server.crt
        ServerTLSCert: ${CONTAINER_PROJECT_ROOT}/build/fabric-bootstrap/orderer/tls/server.crt

  BatchTimeout: 2s

  BatchSize:

    MaxMessageCount: 10
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 2 MB

  Organizations:

  Policies:

    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"

    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"

    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"

    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"

  Capabilities:
    <<: *OrdererCapabilities


Channel: &ChannelDefaults

  Policies:

    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"

    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"

    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"

  Capabilities:
    <<: *ChannelCapabilities


Profiles:

EOF

# ============================================================
# Generate one profile per channel.
# ============================================================

for CHANNEL_NUMBER in $(seq 1 "$LEDGER_COUNT"); do

    CHANNEL_NAME="channel-${CHANNEL_NUMBER}"

    cat >> "$CONFIGTX_FILE" <<EOF
  ${CHANNEL_NAME}:

    <<: *ChannelDefaults

    Orderer:

      <<: *OrdererDefaults

      Organizations:
        - *OrdererOrg

    Application:

      <<: *ApplicationDefaults

      Organizations:
        - *Org1

EOF

done

# ============================================================
# Generate channel blocks.
#
# IMPORTANT:
# FABRIC_CFG_PATH explicitly points configtxgen at the
# directory containing configtx.yaml.
# ============================================================

echo
echo "Generating Fabric channel blocks..."
echo

for CHANNEL_NUMBER in $(seq 1 "$LEDGER_COUNT"); do

    CHANNEL_NAME="channel-${CHANNEL_NUMBER}"
    CHANNEL_OUTPUT_DIR="$CHANNEL_DIR/$CHANNEL_NAME"

    mkdir -p "$CHANNEL_OUTPUT_DIR"

    echo "Generating ${CHANNEL_NAME}..."

    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$PROJECT_ROOT:${CONTAINER_PROJECT_ROOT}" \
        -w "$CONTAINER_BUILD_DIR" \
        -e "FABRIC_CFG_PATH=${CONTAINER_BUILD_DIR}" \
        "$FABRIC_TOOLS_IMAGE" \
        configtxgen \
        -profile "$CHANNEL_NAME" \
        -channelID "$CHANNEL_NAME" \
        -outputBlock "${CONTAINER_BUILD_DIR}/channels/${CHANNEL_NAME}/channel.block"

    echo "  OK: $CHANNEL_OUTPUT_DIR/channel.block"
done

# ============================================================
# Validate generated artifacts.
# ============================================================

echo
echo "Validating generated channel artifacts..."
echo

for CHANNEL_NUMBER in $(seq 1 "$LEDGER_COUNT"); do

    CHANNEL_NAME="channel-${CHANNEL_NUMBER}"
    CHANNEL_BLOCK="$CHANNEL_DIR/$CHANNEL_NAME/channel.block"

    if [ ! -s "$CHANNEL_BLOCK" ]; then

        echo "Error: generated channel block is empty:"
        echo "  $CHANNEL_BLOCK"

        exit 1
    fi

    echo "  ${CHANNEL_NAME}: OK"
done

# ============================================================
# Finished.
# ============================================================

echo
echo "=============================================="
echo " FABRIC-NETWORK generated"
echo "=============================================="
echo

echo "Peers:"
echo "  ${PEER_COUNT}"

echo "Ledgers:"
echo "  ${LEDGER_COUNT}"

echo "Seed:"
echo "  ${SEED}"

echo
echo "Orderer:"
echo "  fabric-orderer-1"
echo "  Count: 1"

echo
echo "Channels:"
echo

python3 - "$TOPOLOGY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    topology = json.load(f)

for channel_name, peers in topology["channels"].items():

    print(f"  {channel_name} ({len(peers)} peers)")

    for peer in peers:
        print(f"    - {peer}")

    print()
PY

echo "Generated:"
echo "  ${TOPOLOGY_FILE}"
echo "  ${CONFIGTX_FILE}"
echo "  ${CHANNEL_DIR}/"

echo
echo "=============================================="