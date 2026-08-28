FROM docker:cli

LABEL org.opencontainers.image.title="Blockchain Logging Prototype VNF"

RUN apk add --no-cache \
    bash \
    gettext

WORKDIR /opt/vnf

COPY entrypoint.sh /opt/vnf/entrypoint.sh
COPY register-peer.sh /opt/vnf/register-peer.sh
COPY enroll-peer.sh /opt/vnf/enroll-peer.sh
COPY start-peer.sh /opt/vnf/start-peer.sh

RUN chmod +x \
    /opt/vnf/entrypoint.sh \
    /opt/vnf/register-peer.sh \
    /opt/vnf/enroll-peer.sh \
    /opt/vnf/start-peer.sh

ENTRYPOINT ["/opt/vnf/entrypoint.sh"]
