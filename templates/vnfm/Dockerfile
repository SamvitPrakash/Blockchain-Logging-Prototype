FROM hyperledger/fabric-tools:2.5.16

LABEL org.opencontainers.image.title="Blockchain Logging Prototype VNFM"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/vnfm

COPY entrypoint.sh /opt/vnfm/entrypoint.sh
COPY join-orderer.sh /opt/vnfm/join-orderer.sh

RUN chmod +x \
    /opt/vnfm/entrypoint.sh \
    /opt/vnfm/join-orderer.sh

ENTRYPOINT ["/opt/vnfm/entrypoint.sh"]