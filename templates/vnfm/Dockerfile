FROM docker:cli

LABEL org.opencontainers.image.title="Blockchain Logging Prototype VNFM"

RUN apk add --no-cache \
    bash \
    gettext

WORKDIR /opt/vnfm

COPY entrypoint.sh /opt/vnfm/entrypoint.sh
COPY start-ca.sh /opt/vnfm/start-ca.sh
COPY start-orderer.sh /opt/vnfm/start-orderer.sh

RUN chmod +x \
    /opt/vnfm/entrypoint.sh \
    /opt/vnfm/start-ca.sh \
    /opt/vnfm/start-orderer.sh

ENTRYPOINT ["/opt/vnfm/entrypoint.sh"]