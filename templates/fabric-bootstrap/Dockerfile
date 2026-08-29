FROM hyperledger/fabric-ca:1.5.17

LABEL org.opencontainers.image.title="Blockchain Logging Prototype FABRIC-BOOTSTRAP"

RUN apk add --no-cache \
    bash \
    gettext

WORKDIR /opt/fabric-bootstrap

COPY entrypoint.sh /opt/fabric-bootstrap/entrypoint.sh
COPY start-orderer.sh /opt/fabric-bootstrap/start-orderer.sh

RUN chmod +x \
    /opt/fabric-bootstrap/entrypoint.sh \
    /opt/fabric-bootstrap/start-orderer.sh

ENTRYPOINT ["/opt/fabric-bootstrap/entrypoint.sh"]