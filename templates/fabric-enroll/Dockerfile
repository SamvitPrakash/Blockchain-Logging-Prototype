FROM hyperledger/fabric-ca:1.5.17 AS fabric-ca

FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="Blockchain Logging Prototype FABRIC-ENROLL"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        gettext-base \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fabric-ca /usr/local/bin/fabric-ca-client /usr/local/bin/fabric-ca-client

WORKDIR /opt/fabric-enroll

COPY entrypoint.sh /opt/fabric-enroll/entrypoint.sh
COPY register-peer.sh /opt/fabric-enroll/register-peer.sh
COPY enroll-peer.sh /opt/fabric-enroll/enroll-peer.sh
COPY prepare-peer.sh /opt/fabric-enroll/prepare-peer.sh

RUN chmod +x \
    /opt/fabric-enroll/entrypoint.sh \
    /opt/fabric-enroll/register-peer.sh \
    /opt/fabric-enroll/enroll-peer.sh \
    /opt/fabric-enroll/prepare-peer.sh

ENTRYPOINT ["/opt/fabric-enroll/entrypoint.sh"]