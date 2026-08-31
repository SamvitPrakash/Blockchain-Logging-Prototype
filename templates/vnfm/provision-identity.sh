#!/bin/bash

set -euo pipefail

# ============================================================
# VNFM Identity Provisioning
# ============================================================

OUTPUT_DIR="${1:?Output directory is required}"
CA_ENDPOINT="${2:?CA endpoint is required}"
IDENTITY_NAME="${3:?Identity name is required}"
IDENTITY_PASSWORD="${4:?Identity password is required}"

ADMIN_MSP_DIR="${OUTPUT_DIR}/msp"
CLIENT_DIR="${OUTPUT_DIR}/client"

CA_ADMIN_HOME="${CLIENT_DIR}/ca-admin"
VNFM_CLIENT_HOME="${CLIENT_DIR}/vnfm"

# ============================================================
# Validation
# ============================================================

if [ -z "$OUTPUT_DIR" ] || [ -z "$CA_ENDPOINT" ]; then
    echo "ERROR: invalid identity provisioning arguments."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================================
# Clean previous generated identity
# ============================================================

rm -rf "$ADMIN_MSP_DIR"
rm -rf "$CA_ADMIN_HOME"
rm -rf "$VNFM_CLIENT_HOME"

mkdir -p \
    "$CA_ADMIN_HOME" \
    "$VNFM_CLIENT_HOME" \
    "$ADMIN_MSP_DIR"

# ============================================================
# Fabric CA client configuration
# ============================================================

export FABRIC_CA_CLIENT_HOME="$CA_ADMIN_HOME"

# ============================================================
# Enroll CA administrator
# ============================================================

echo
echo "=============================================="
echo " Registering VNFM"
echo "=============================================="
echo

echo "VNFM:"
echo "  ${IDENTITY_NAME}"

echo "CA:"
echo "  ${CA_ENDPOINT}"

echo "State:"
echo "  ${OUTPUT_DIR}"

echo
echo "Enrolling CA administrator..."

fabric-ca-client enroll \
    -u "http://admin:adminpw@${CA_ENDPOINT}" \
    --caname ca-fabric \
    --tls.certfiles "$CA_ADMIN_HOME/msp/cacerts/"*.pem

# ============================================================
# Register VNFM as an administrative identity
# ============================================================

echo
echo "Registering VNFM administrative identity..."

fabric-ca-client register \
    --caname ca-fabric \
    --id.name "$IDENTITY_NAME" \
    --id.secret "$IDENTITY_PASSWORD" \
    --id.type admin \
    --id.affiliation org1

# ============================================================
# Enroll VNFM identity
# ============================================================

echo
echo "=============================================="
echo " Enrolling VNFM administrator"
echo "=============================================="
echo

export FABRIC_CA_CLIENT_HOME="$VNFM_CLIENT_HOME"

fabric-ca-client enroll \
    -u "http://${IDENTITY_NAME}:${IDENTITY_PASSWORD}@${CA_ENDPOINT}" \
    --caname ca-fabric \
    -M "$ADMIN_MSP_DIR" \
    --csr.cn "$IDENTITY_NAME" \
    --csr.names "C=ZA,ST=Gauteng,L=Johannesburg,O=Org1,OU=ADMIN" \
    --tls.certfiles "$CA_ADMIN_HOME/msp/cacerts/"*.pem

# ============================================================
# Configure NodeOUs
#
# The peer enrollment flow in this repository requires the
# admin OU to be explicitly represented in config.yaml.
# ============================================================

CA_CERT_NAME="$(basename "$ADMIN_MSP_DIR/cacerts/"*.pem)"

cat > "$ADMIN_MSP_DIR/config.yaml" <<EOF
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    Certificate: cacerts/${CA_CERT_NAME}
    OrganizationalUnitIdentifier: client

  PeerOUIdentifier:
    Certificate: cacerts/${CA_CERT_NAME}
    OrganizationalUnitIdentifier: peer

  AdminOUIdentifier:
    Certificate: cacerts/${CA_CERT_NAME}
    OrganizationalUnitIdentifier: admin

  OrdererOUIdentifier:
    Certificate: cacerts/${CA_CERT_NAME}
    OrganizationalUnitIdentifier: orderer
EOF

# ============================================================
# Copy CA certificate into standard MSP structure
# ============================================================

mkdir -p "$ADMIN_MSP_DIR/tlscacerts"

cp \
    "$ADMIN_MSP_DIR/cacerts/"*.pem \
    "$ADMIN_MSP_DIR/tlscacerts/ca.crt"

# ============================================================
# Verify identity
# ============================================================

if [ ! -f "$ADMIN_MSP_DIR/signcerts/cert.pem" ]; then
    echo
    echo "ERROR: VNFM administrator certificate was not generated."
    exit 1
fi

if [ ! -d "$ADMIN_MSP_DIR/keystore" ]; then
    echo
    echo "ERROR: VNFM administrator keystore was not generated."
    exit 1
fi

if [ ! -f "$ADMIN_MSP_DIR/config.yaml" ]; then
    echo
    echo "ERROR: VNFM administrator MSP config.yaml was not generated."
    exit 1
fi

# ============================================================
# Finished
# ============================================================

echo
echo "=============================================="
echo " VNFM identity provisioned"
echo "=============================================="
echo

echo "Identity:"
echo "  ${IDENTITY_NAME}"

echo "Type:"
echo "  admin"

echo "MSP:"
echo "  ${ADMIN_MSP_DIR}"

echo