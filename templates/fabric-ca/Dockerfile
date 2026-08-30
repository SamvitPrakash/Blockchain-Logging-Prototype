FROM hyperledger/fabric-ca:1.5.17

LABEL org.opencontainers.image.title="Blockchain Logging Prototype FABRIC-CA"

ENV FABRIC_CA_HOME=/opt/fabric-ca-state

COPY ca-server-config.yaml \
    /opt/fabric-ca-state/fabric-ca-server-config.yaml

EXPOSE 7054

CMD ["fabric-ca-server", "start", \
     "-c", "/opt/fabric-ca-state/fabric-ca-server-config.yaml", \
     "-b", "admin:adminpw"]