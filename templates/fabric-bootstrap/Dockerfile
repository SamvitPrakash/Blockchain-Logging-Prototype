FROM hyperledger/fabric-ca:1.5.17

LABEL org.opencontainers.image.title="Blockchain Logging Prototype FABRIC-BOOTSTRAP"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        gettext \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/fabric-bootstrap

COPY entrypoint.sh /opt/fabric-bootstrap/entrypoint.sh
COPY enroll-orderer.sh /opt/fabric-bootstrap/enroll-orderer.sh

RUN chmod +x \
    /opt/fabric-bootstrap/entrypoint.sh \
    /opt/fabric-bootstrap/enroll-orderer.sh

ENTRYPOINT ["/opt/fabric-bootstrap/entrypoint.sh"]