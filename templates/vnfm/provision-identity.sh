#!/bin/bash

set -euo pipefail

# ============================================================
# VNFM Identity Provisioner
# ============================================================

OUTPUT_DIR="${1:?Missing output directory}"
CA_ENDPOINT="${2:?Missing CA endpoint}"
IDENTITY_NAME="${3:?Missing identity name}"
IDENTITY_PASSWORD="${4:?Missing identity password}"

CA_CLIENT_IMAGE="hyperledger/fabric-ca:1.5.15"

CLIENT_HOME="/tmp/fabric-ca-client"
VNFM_MSP="${CLIENT_HOME}/vnfm-msp"

# ============================================================
# Prepare output directory
# ============================================================

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ============================================================
# Check Fabric CA
# ============================================================

echo "Checking Fabric CA..."

docker run --rm \
    --network XIT \
    "$CA_CLIENT_IMAGE" \
    fabric-ca-client version >/dev/null

echo "Fabric CA:"
echo "  reachable"
echo

# ============================================================
# Register and enroll VNFM identity
#
# Everything involving the Fabric CA client filesystem occurs
# inside ONE temporary container.
#
# Only the three credentials required by the VNFM are exported
# through /output.
# ============================================================

echo "Registering VNFM identity..."
echo

docker run --rm \
    --network XIT \
    -v "${OUTPUT_DIR}:/output" \
    "$CA_CLIENT_IMAGE" \
    sh -c "
        set -e

        export FABRIC_CA_CLIENT_HOME='${CLIENT_HOME}'

        rm -rf '${CLIENT_HOME}'
        mkdir -p '${CLIENT_HOME}'

        # ----------------------------------------------------
        # Enroll Fabric CA administrator
        # ----------------------------------------------------

        fabric-ca-client enroll \
            -u 'http://admin:adminpw@${CA_ENDPOINT}' \
            --caname ca

        # ----------------------------------------------------
        # Register VNFM identity
        # ----------------------------------------------------

        fabric-ca-client register \
            --id.name '${IDENTITY_NAME}' \
            --id.secret '${IDENTITY_PASSWORD}' \
            --id.type client \
            -u 'http://${CA_ENDPOINT}'

        echo
        echo 'VNFM identity registered.'
        echo
        echo 'Enrolling VNFM identity...'

        # ----------------------------------------------------
        # Enroll VNFM identity
        # ----------------------------------------------------

        fabric-ca-client enroll \
            -u 'http://${IDENTITY_NAME}:${IDENTITY_PASSWORD}@${CA_ENDPOINT}' \
            --caname ca \
            -M '${VNFM_MSP}'

        # ----------------------------------------------------
        # Locate generated credentials
        # ----------------------------------------------------

        CLIENT_CERT='${VNFM_MSP}/signcerts/cert.pem'

        CLIENT_KEY=\$(find '${VNFM_MSP}/keystore' \
            -type f \
            -print \
            -quit)

        CA_CERT=\$(find '${VNFM_MSP}/cacerts' \
            -type f \
            -print \
            -quit)

        # ----------------------------------------------------
        # Validate credentials
        # ----------------------------------------------------

        if [ ! -f \"\$CLIENT_CERT\" ]; then
            echo
            echo 'ERROR: VNFM client certificate was not generated.'
            exit 1
        fi

        if [ -z \"\$CLIENT_KEY\" ] || [ ! -f \"\$CLIENT_KEY\" ]; then
            echo
            echo 'ERROR: VNFM client private key was not generated.'
            echo
            echo 'VNFM MSP contents:'
            find '${VNFM_MSP}' -maxdepth 3 -type f -print
            exit 1
        fi

        if [ -z \"\$CA_CERT\" ] || [ ! -f \"\$CA_CERT\" ]; then
            echo
            echo 'ERROR: VNFM CA certificate was not generated.'
            exit 1
        fi

        # ----------------------------------------------------
        # Export credentials
        # ----------------------------------------------------

        cp \"\$CLIENT_CERT\" \
            /output/client.crt

        cp \"\$CLIENT_KEY\" \
            /output/client.key

        cp \"\$CA_CERT\" \
            /output/ca.crt

        chmod 600 \
            /output/client.key

        chmod 644 \
            /output/client.crt \
            /output/ca.crt

        # ----------------------------------------------------
        # Final validation
        # ----------------------------------------------------

        test -s /output/client.crt
        test -s /output/client.key
        test -s /output/ca.crt

        echo
        echo 'VNFM credentials exported successfully.'
    "

# ============================================================
# Host-side validation
# ============================================================

if [ ! -s "${OUTPUT_DIR}/client.crt" ]; then
    echo "Error: VNFM client certificate was not exported."
    exit 1
fi

if [ ! -s "${OUTPUT_DIR}/client.key" ]; then
    echo "Error: VNFM client private key was not exported."
    exit 1
fi

if [ ! -s "${OUTPUT_DIR}/ca.crt" ]; then
    echo "Error: VNFM CA certificate was not exported."
    exit 1
fi

# ============================================================
# Finished
# ============================================================

echo
echo "VNFM credentials:"
echo "  ${OUTPUT_DIR}"
echo
echo "  ca.crt"
echo "  client.crt"
echo "  client.key"