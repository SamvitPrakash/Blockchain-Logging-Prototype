FROM hyperledger/fabric-ca:1.5.17

LABEL org.opencontainers.image.title="Blockchain Logging Prototype FABRIC-CA"

COPY ca-server-config.yaml \
    /etc/hyperledger/fabric-ca-server/fabric-ca-server-config.yaml

ENV FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server

EXPOSE 7054

CMD ["fabric-ca-server", "start", \
     "-c", "/etc/hyperledger/fabric-ca-server/fabric-ca-server-config.yaml", \
     "-b", "admin:adminpw"]