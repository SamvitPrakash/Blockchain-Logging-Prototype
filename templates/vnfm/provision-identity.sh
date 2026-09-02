#!/bin/bash

set -euo pipefail

OUTPUT_DIR="${1:?Missing output directory}"
CA_ENDPOINT="${2:?Missing CA endpoint}"
CLIENT_IDENTITY="${3:?Missing client identity}"
CLIENT_PASSWORD="${4:?Missing client password}"
ADMIN_IDENTITY="${5:?Missing admin identity}"
ADMIN_PASSWORD="${6:?Missing admin password}"
CA_CLIENT_IMAGE="${7:-hyperledger/fabric-ca:1.5.15}"

CLIENT_HOME="/tmp/fabric-ca-client"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo
echo "=============================================="
echo " Registering VNFM identities"
echo "=============================================="
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

        echo 'Enrolling CA administrator...'

        fabric-ca-client enroll \
            -u 'http://admin:adminpw@${CA_ENDPOINT}' \
            --caname ca

        # ====================================================
        # VNFM client identity
        #
        # Used by osnadmin for the orderer Admin API.
        # ====================================================

        echo
        echo 'Registering VNFM client identity...'

        fabric-ca-client register \
            --id.name '${CLIENT_IDENTITY}' \
            --id.secret '${CLIENT_PASSWORD}' \
            --id.affiliation org1 \
            --id.type client \
            -u 'http://${CA_ENDPOINT}'

        echo
        echo 'Enrolling VNFM client identity...'

        CLIENT_HOME_DIR='${CLIENT_HOME}/vnfm-client'

        mkdir -p \"\$CLIENT_HOME_DIR\"

        fabric-ca-client enroll \
            -u 'http://${CLIENT_IDENTITY}:${CLIENT_PASSWORD}@${CA_ENDPOINT}' \
            --caname ca \
            --home \"\$CLIENT_HOME_DIR\" \
            -M /output/client-msp

        CLIENT_CERT='/output/client-msp/signcerts/cert.pem'
        CLIENT_KEY=\$(find /output/client-msp/keystore -type f -print -quit)
        CA_CERT=\$(find /output/client-msp/cacerts -type f -print -quit)

        test -s \"\$CLIENT_CERT\"
        test -n \"\$CLIENT_KEY\"
        test -s \"\$CLIENT_KEY\"
        test -n \"\$CA_CERT\"
        test -s \"\$CA_CERT\"

        cp \"\$CLIENT_CERT\" /output/client.crt
        cp \"\$CLIENT_KEY\" /output/client.key
        cp \"\$CA_CERT\" /output/ca.crt

        # ====================================================
        # VNFM administrative identity
        #
        # This is separate from the client identity.
        # ====================================================

        echo
        echo 'Registering VNFM admin identity...'

        fabric-ca-client register \
            --id.name '${ADMIN_IDENTITY}' \
            --id.secret '${ADMIN_PASSWORD}' \
            --id.affiliation org1 \
            --id.type admin \
            -u 'http://${CA_ENDPOINT}'

        echo
        echo 'Enrolling VNFM admin identity...'

        ADMIN_HOME_DIR='${CLIENT_HOME}/vnfm-admin'

        mkdir -p \"\$ADMIN_HOME_DIR\"

        fabric-ca-client enroll \
            -u 'http://${ADMIN_IDENTITY}:${ADMIN_PASSWORD}@${CA_ENDPOINT}' \
            --caname ca \
            --home \"\$ADMIN_HOME_DIR\" \
            -M /output/admin-msp \
            --csr.cn '${ADMIN_IDENTITY}'

        ADMIN_CA_CERT=\$(find /output/admin-msp/cacerts -type f -print -quit)

        test -n \"\$ADMIN_CA_CERT\"
        test -s \"\$ADMIN_CA_CERT\"

        # ====================================================
        # NodeOUs
        # ====================================================

        cat > /output/admin-msp/config.yaml <<EOF
NodeOUs:
  Enable: true

  ClientOUIdentifier:
    Certificate: cacerts/\$(basename \"\$ADMIN_CA_CERT\")
    OrganizationalUnitIdentifier: client

  PeerOUIdentifier:
    Certificate: cacerts/\$(basename \"\$ADMIN_CA_CERT\")
    OrganizationalUnitIdentifier: peer

  AdminOUIdentifier:
    Certificate: cacerts/\$(basename \"\$ADMIN_CA_CERT\")
    OrganizationalUnitIdentifier: admin

  OrdererOUIdentifier:
    Certificate: cacerts/\$(basename \"\$ADMIN_CA_CERT\")
    OrganizationalUnitIdentifier: orderer
EOF

        # ====================================================
        # Standard MSP structure
        # ====================================================

        mkdir -p /output/admin-msp/tlscacerts

        cp \"\$ADMIN_CA_CERT\" \
           /output/admin-msp/tlscacerts/ca.crt

        chmod 600 /output/client.key

        chmod 644 \
            /output/client.crt \
            /output/ca.crt

        echo
        echo 'VNFM identities generated successfully.'
    "

# ------------------------------------------------------------
# Validate client credentials
# ------------------------------------------------------------

test -s "$OUTPUT_DIR/client.crt"
test -s "$OUTPUT_DIR/client.key"
test -s "$OUTPUT_DIR/ca.crt"

# ------------------------------------------------------------
# Validate admin MSP
# ------------------------------------------------------------

test -s "$OUTPUT_DIR/admin-msp/signcerts/cert.pem"
test -s "$OUTPUT_DIR/admin-msp/config.yaml"

ADMIN_KEY="$(find "$OUTPUT_DIR/admin-msp/keystore" -type f -print -quit)"

if [ -z "$ADMIN_KEY" ] || [ ! -s "$ADMIN_KEY" ]; then
    echo "Error: VNFM admin private key was not generated."
    exit 1
fi

echo
echo "=============================================="
echo " VNFM identities ready"
echo "=============================================="
echo

echo "Client:"
echo "  $OUTPUT_DIR/client.crt"
echo "  $OUTPUT_DIR/client.key"

echo
echo "Admin MSP:"
echo "  $OUTPUT_DIR/admin-msp"

echo