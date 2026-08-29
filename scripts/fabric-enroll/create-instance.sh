#!/bin/bash

set -euo pipefail

# ============================================================
# FABRIC-ENROLL Instance Generator
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEMPLATE_DIR="$PROJECT_ROOT/templates/fabric-enroll"
BUILD_DIR="$PROJECT_ROOT/build/fabric-enroll-${INSTANCE}"
HOST_PEER_STATE_DIR="$BUILD_DIR/peer"

# ============================================================
# Naming
# ============================================================

VNF_NAME="fabric-enroll-${INSTANCE}"
VNF_CONTAINER="fabric-enroll-${INSTANCE}"
PEER_NAME="fabric-peer-${INSTANCE}"

OAM_NETWORK="OAM-${INSTANCE}"
OAM_IP="10.20.${INSTANCE}.3"

XIT_NETWORK="XIT"
VNF_XIT_IP="10.10.0.$((50 + INSTANCE))"
PEER_IP="10.10.0.$((100 + INSTANCE))"

# ============================================================
# Host ownership
# ============================================================

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# ============================================================
# Peer configuration
# ============================================================

PEER_SECRET="peerpw"
PEER_HOSTNAME="${PEER_NAME}"

PEER_STATE_DIR="/opt/fabric-enroll-state/peer"

CA_IP="10.10.0.11"

# ============================================================
# Validation
# ============================================================

for file in \
    Dockerfile \
    entrypoint.sh \
    register-peer.sh \
    enroll-peer.sh \
    prepare-peer.sh
do
    if [ ! -f "$TEMPLATE_DIR/$file" ]; then
        echo "Error: FABRIC-ENROLL template file not found:"
        echo "  $TEMPLATE_DIR/$file"
        exit 1
    fi
done

if docker inspect "$VNF_CONTAINER" >/dev/null 2>&1; then
    echo "Error: FABRIC-ENROLL container '${VNF_CONTAINER}' already exists."
    exit 1
fi

if docker inspect "$PEER_NAME" >/dev/null 2>&1; then
    echo "Error: Fabric peer container '${PEER_NAME}' already exists."
    exit 1
fi

if ! docker network inspect "$OAM_NETWORK" >/dev/null 2>&1; then
    echo "Error: OAM network '${OAM_NETWORK}' does not exist."
    echo
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/OAM/create-oam-network.sh ${INSTANCE}"
    echo
    exit 1
fi

if ! docker network inspect "$XIT_NETWORK" >/dev/null 2>&1; then
    echo "Error: XIT network does not exist."
    echo
    echo "Create it first with:"
    echo
    echo "  ./scripts/networks/XIT/setup-XIT.sh"
    echo
    exit 1
fi

if [ -d "$BUILD_DIR" ]; then
    echo "Error: build directory already exists:"
    echo "  $BUILD_DIR"
    echo
    echo "Remove it first if you want to regenerate the instance:"
    echo
    echo "  rm -rf ${BUILD_DIR}"
    echo
    exit 1
fi

# ============================================================
# Create build directories
# ============================================================

mkdir -p \
    "$BUILD_DIR" \
    "$HOST_PEER_STATE_DIR"

# ============================================================
# Build FABRIC-ENROLL image
# ============================================================

IMAGE_NAME="blockchain-fabric-enroll:latest"

docker build \
    -t "$IMAGE_NAME" \
    "$TEMPLATE_DIR"

# ============================================================
# Generate Compose
# ============================================================

cat > "$BUILD_DIR/compose.yaml" <<EOF
services:

  # ==========================================================
  # Fabric enrollment
  # ==========================================================

  ${VNF_CONTAINER}:
    image: ${IMAGE_NAME}
    container_name: ${VNF_CONTAINER}
    hostname: ${VNF_CONTAINER}

    privileged: true

    environment:
      VNF_INSTANCE: "${INSTANCE}"
      VNF_STATE_DIR: "/opt/fabric-enroll-state"
      VNF_NAME: "${VNF_NAME}"

      OAM_NETWORK: "${OAM_NETWORK}"
      OAM_IP: "${OAM_IP}"

      XIT_NETWORK: "${XIT_NETWORK}"

      PEER_NAME: "${PEER_NAME}"
      PEER_SECRET: "${PEER_SECRET}"
      PEER_HOSTNAME: "${PEER_HOSTNAME}"
      PEER_IP: "${PEER_IP}"
      PEER_STATE_DIR: "${PEER_STATE_DIR}"

      CA_IP: "${CA_IP}"

      HOST_UID: "${HOST_UID}"
      HOST_GID: "${HOST_GID}"
      HOST_PEER_STATE_DIR: "${HOST_PEER_STATE_DIR}"

    volumes:
      - ${BUILD_DIR}:/opt/fabric-enroll-state

    networks:
      oam:
        ipv4_address: ${OAM_IP}

      xit:
        ipv4_address: ${VNF_XIT_IP}

    restart: "no"

  # ==========================================================
  # Fabric peer
  # ==========================================================

  ${PEER_NAME}:
    image: hyperledger/fabric-peer:2.5
    container_name: ${PEER_NAME}
    hostname: ${PEER_HOSTNAME}

    depends_on:
      ${VNF_CONTAINER}:
        condition: service_completed_successfully

    environment:
      FABRIC_CFG_PATH: "/etc/hyperledger/fabric"

      CORE_PEER_ID: "${PEER_NAME}"
      CORE_PEER_ADDRESS: "${PEER_HOSTNAME}:7051"
      CORE_PEER_LISTENADDRESS: "0.0.0.0:7051"

      CORE_PEER_LOCALMSPID: "Org1MSP"
      CORE_PEER_MSPCONFIGPATH: "/etc/hyperledger/fabric/msp"

      CORE_PEER_TLS_ENABLED: "true"
      CORE_PEER_TLS_CERT_FILE: "/etc/hyperledger/fabric/tls/server.crt"
      CORE_PEER_TLS_KEY_FILE: "/etc/hyperledger/fabric/tls/server.key"
      CORE_PEER_TLS_ROOTCERT_FILE: "/etc/hyperledger/fabric/tls/ca.crt"

    volumes:
      - ${HOST_PEER_STATE_DIR}:/etc/hyperledger/fabric:rw
      - ${HOST_PEER_STATE_DIR}/production:/var/hyperledger/production:rw
      - /var/run/docker.sock:/var/run/docker.sock

    command:
      - peer
      - node
      - start

    networks:
      xit:
        ipv4_address: ${PEER_IP}

    restart: unless-stopped

networks:

  oam:
    external: true
    name: ${OAM_NETWORK}

  xit:
    external: true
    name: ${XIT_NETWORK}
EOF

# ============================================================
# Generate host-side register helper
# ============================================================

cat > "$BUILD_DIR/register-peer.sh" <<EOF
#!/bin/bash

set -euo pipefail

docker exec \
    -e VNF_INSTANCE="${INSTANCE}" \
    -e VNF_NAME="${VNF_NAME}" \
    -e VNF_STATE_DIR="/opt/fabric-enroll-state" \
    -e PEER_NAME="${PEER_NAME}" \
    -e PEER_SECRET="${PEER_SECRET}" \
    -e PEER_HOSTNAME="${PEER_HOSTNAME}" \
    -e PEER_IP="${PEER_IP}" \
    -e PEER_STATE_DIR="${PEER_STATE_DIR}" \
    -e CA_IP="${CA_IP}" \
    "${VNF_CONTAINER}" \
    /opt/fabric-enroll/register-peer.sh
EOF

# ============================================================
# Generate host-side enroll helper
# ============================================================

cat > "$BUILD_DIR/enroll-peer.sh" <<EOF
#!/bin/bash

set -euo pipefail

docker exec \
    -e VNF_INSTANCE="${INSTANCE}" \
    -e VNF_NAME="${VNF_NAME}" \
    -e VNF_STATE_DIR="/opt/fabric-enroll-state" \
    -e PEER_NAME="${PEER_NAME}" \
    -e PEER_SECRET="${PEER_SECRET}" \
    -e PEER_HOSTNAME="${PEER_HOSTNAME}" \
    -e PEER_IP="${PEER_IP}" \
    -e PEER_STATE_DIR="${PEER_STATE_DIR}" \
    -e CA_IP="${CA_IP}" \
    -e HOST_UID="${HOST_UID}" \
    -e HOST_GID="${HOST_GID}" \
    "${VNF_CONTAINER}" \
    /opt/fabric-enroll/enroll-peer.sh
EOF

# ============================================================
# Generate host-side start helper
# ============================================================

cat > "$BUILD_DIR/start-peer.sh" <<EOF
#!/bin/bash

set -euo pipefail

docker compose \
    -f "${BUILD_DIR}/compose.yaml" \
    up -d "${PEER_NAME}"
EOF

chmod +x \
    "$BUILD_DIR/register-peer.sh" \
    "$BUILD_DIR/enroll-peer.sh" \
    "$BUILD_DIR/start-peer.sh"

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " FABRIC-ENROLL instance generated"
echo "=============================================="
echo
echo "FABRIC-ENROLL:"
echo "  Name       : ${VNF_NAME}"
echo "  Container  : ${VNF_CONTAINER}"
echo "  OAM        : ${OAM_NETWORK}"
echo "  OAM IP     : ${OAM_IP}"
echo "  XIT IP     : ${VNF_XIT_IP}"
echo
echo "Fabric peer:"
echo "  Name       : ${PEER_NAME}"
echo "  Hostname   : ${PEER_HOSTNAME}"
echo "  XIT IP     : ${PEER_IP}"
echo
echo "State:"
echo "  Container  : ${PEER_STATE_DIR}"
echo "  Host       : ${HOST_PEER_STATE_DIR}"
echo
echo "Host:"
echo "  UID        : ${HOST_UID}"
echo "  GID        : ${HOST_GID}"
echo
echo "Generated:"
echo "  ${BUILD_DIR}/compose.yaml"
echo "  ${BUILD_DIR}/register-peer.sh"
echo "  ${BUILD_DIR}/enroll-peer.sh"
echo "  ${BUILD_DIR}/start-peer.sh"
echo
echo "Start FABRIC-ENROLL with:"
echo
echo "  docker compose -f ${BUILD_DIR}/compose.yaml up -d"
echo
echo "The peer will start automatically after enrollment succeeds."
echo