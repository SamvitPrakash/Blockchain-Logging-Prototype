#!/bin/bash

set -e

# ============================================================
# Open5GS / UERANSIM Instance Generator
# ============================================================

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance-number>"
    exit 1
fi

INSTANCE="$1"

if ! [[ "$INSTANCE" =~ ^[0-9]+$ ]] || [ "$INSTANCE" -lt 1 ]; then
    echo "Error: instance number must be a positive integer."
    exit 1
fi

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCKER_OPEN5GS="$PROJECT_ROOT/docker_open5gs"
BUILD_DIR="$PROJECT_ROOT/build"

GNB_TEMPLATE="$PROJECT_ROOT/templates/gnb/config.yaml"
UE_TEMPLATE="$PROJECT_ROOT/templates/ue/config.yaml"

GNB_BUILD_DIR="$BUILD_DIR/gnb-${INSTANCE}"
UE_BUILD_DIR="$BUILD_DIR/ue-${INSTANCE}"

# ============================================================
# Open5GS configuration
# ============================================================

MCC="001"
MNC="01"
TAC="1"

AMF_IP="172.22.0.10"

# ============================================================
# Instance-specific network configuration
# ============================================================

GNB_IP="172.22.0.$((40 + (INSTANCE - 1) * 2))"
UE_IP="172.22.0.$((41 + (INSTANCE - 1) * 2))"

NCI=$(printf "0x%09x" "$INSTANCE")

GNB_CONTAINER="nr_gnb_${INSTANCE}"
UE_CONTAINER="nr_ue_${INSTANCE}"

# ============================================================
# Subscriber configuration
# ============================================================

IMSI="00101$(printf "%010d" "$INSTANCE")"

KI="8baf473f2f8fd09487cccbd7097c6862"
OP="11111111111111111111111111111111"
UE_AMF="8000"

IMEI="356938035643803"
IMEISV="4370816125816$(printf "%03d" "$INSTANCE")"

# ============================================================
# Validate required files
# ============================================================

if [ ! -f "$GNB_TEMPLATE" ]; then
    echo "Error: gNB template not found:"
    echo "  $GNB_TEMPLATE"
    exit 1
fi

if [ ! -f "$UE_TEMPLATE" ]; then
    echo "Error: UE template not found:"
    echo "  $UE_TEMPLATE"
    exit 1
fi

if [ ! -f "$DOCKER_OPEN5GS/ueransim/ueransim-gnb_init.sh" ]; then
    echo "Error: UERANSIM gNB init script not found."
    exit 1
fi

if [ ! -f "$DOCKER_OPEN5GS/ueransim/ueransim-ue_init.sh" ]; then
    echo "Error: UERANSIM UE init script not found."
    exit 1
fi

# ============================================================
# Check MongoDB
# ============================================================

if ! docker ps --format '{{.Names}}' | grep -qx "mongo"; then
    echo "Error: MongoDB container 'mongo' is not running."
    exit 1
fi

# ============================================================
# Check for duplicate instance
# ============================================================

if [ -d "$GNB_BUILD_DIR" ] || [ -d "$UE_BUILD_DIR" ]; then
    echo "Error: instance ${INSTANCE} already exists."
    echo
    echo "Existing directories:"
    [ -d "$GNB_BUILD_DIR" ] && echo "  $GNB_BUILD_DIR"
    [ -d "$UE_BUILD_DIR" ] && echo "  $UE_BUILD_DIR"
    exit 1
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p "$GNB_BUILD_DIR"
mkdir -p "$UE_BUILD_DIR"

# ============================================================
# Copy upstream UERANSIM initialization scripts
# ============================================================

cp "$DOCKER_OPEN5GS/ueransim/ueransim-gnb_init.sh" \
   "$GNB_BUILD_DIR/ueransim-gnb_init.sh"

cp "$DOCKER_OPEN5GS/ueransim/ueransim-ue_init.sh" \
   "$UE_BUILD_DIR/ueransim-ue_init.sh"

chmod +x "$GNB_BUILD_DIR/ueransim-gnb_init.sh"
chmod +x "$UE_BUILD_DIR/ueransim-ue_init.sh"

# ============================================================
# Generate gNB configuration
# ============================================================

export MCC
export MNC
export TAC
export NCI
export GNB_IP
export AMF_IP

envsubst < "$GNB_TEMPLATE" \
    > "$GNB_BUILD_DIR/ueransim-gnb.yaml"

# ============================================================
# Generate UE configuration
# ============================================================

export IMSI
export KI
export OP
export UE_AMF
export IMEI
export IMEISV
export GNB_IP

envsubst < "$UE_TEMPLATE" \
    > "$UE_BUILD_DIR/ueransim-ue.yaml"

# ============================================================
# Generate gNB Docker Compose
# ============================================================

cat > "$GNB_BUILD_DIR/compose.yaml" <<EOF
services:
  ${GNB_CONTAINER}:
    image: docker_ueransim
    container_name: ${GNB_CONTAINER}
    stdin_open: true
    tty: true

    volumes:
      - ${GNB_BUILD_DIR}:/mnt/ueransim
      - /etc/localtime:/etc/localtime:ro

    environment:
      COMPONENT_NAME: ueransim-gnb

    expose:
      - "38412/sctp"
      - "2152/udp"
      - "4997/udp"

    cap_add:
      - NET_ADMIN

    privileged: true

    networks:
      default:
        ipv4_address: ${GNB_IP}

networks:
  default:
    external: true
    name: docker_open5gs_default
EOF

# ============================================================
# Generate UE Docker Compose
# ============================================================

cat > "$UE_BUILD_DIR/compose.yaml" <<EOF
services:
  ${UE_CONTAINER}:
    image: docker_ueransim
    container_name: ${UE_CONTAINER}
    stdin_open: true
    tty: true

    volumes:
      - ${UE_BUILD_DIR}:/mnt/ueransim
      - /etc/localtime:/etc/localtime:ro

    environment:
      COMPONENT_NAME: ueransim-ue

    expose:
      - "4997/udp"

    cap_add:
      - NET_ADMIN

    privileged: true

    networks:
      default:
        ipv4_address: ${UE_IP}

networks:
  default:
    external: true
    name: docker_open5gs_default
EOF

# ============================================================
# Insert subscriber into MongoDB
# ============================================================

docker exec mongo mongosh --quiet open5gs --eval "
if (db.subscribers.countDocuments({imsi: '${IMSI}'}) > 0) {
    print('ERROR: Subscriber ${IMSI} already exists.');
    quit(1);
}

db.subscribers.insertOne({
    schema_version: 1,
    msisdn: [],
    imeisv: '${IMEISV}',
    mme_host: [],
    mme_realm: [],
    purge_flag: [],
    access_restriction_data: 32,
    subscriber_status: 0,
    operator_determined_barring: 0,
    network_access_mode: 0,
    subscribed_rau_tau_timer: 12,

    imsi: '${IMSI}',

    security: {
        k: '${KI}',
        amf: '${UE_AMF}',
        op: '${OP}',
        opc: null,
        sqn: NumberLong('0')
    },

    ambr: {
        downlink: { value: 1, unit: 3 },
        uplink: { value: 1, unit: 3 }
    },

    slice: [{
        sst: 1,
        default_indicator: true,
        session: [{
            name: 'internet',
            type: 3,
            qos: {
                arp: {
                    priority_level: 8,
                    pre_emption_capability: 1,
                    pre_emption_vulnerability: 1
                },
                index: 9
            },
            ambr: {
                downlink: { value: 1, unit: 3 },
                uplink: { value: 1, unit: 3 }
            },
            pcc_rule: []
        }]
    }],

    __v: 0
});
"

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " Instance ${INSTANCE} created successfully"
echo "=============================================="
echo
echo "gNB:"
echo "  Container : ${GNB_CONTAINER}"
echo "  IP        : ${GNB_IP}"
echo "  NCI       : ${NCI}"
echo
echo "UE:"
echo "  Container : ${UE_CONTAINER}"
echo "  IP        : ${UE_IP}"
echo "  IMSI      : ${IMSI}"
echo
echo "Subscriber:"
echo "  MongoDB   : open5gs.subscribers"
echo "  IMSI      : ${IMSI}"
echo
echo "Generated:"
echo "  ${GNB_BUILD_DIR}"
echo "  ${UE_BUILD_DIR}"
echo