FROM node:20-bookworm-slim

WORKDIR /opt/vnf

# Install tools required by the existing Fabric CA scripts.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        bash \
        openssl \
        && rm -rf /var/lib/apt/lists/*

# Fabric CA client
RUN curl -fsSL \
    https://github.com/hyperledger/fabric-ca/releases/download/v1.5.17/hyperledger-fabric-ca-linux-amd64-1.5.17.tar.gz \
    -o /tmp/fabric-ca.tar.gz && \
    tar -xzf /tmp/fabric-ca.tar.gz -C /tmp && \
    mv /tmp/bin/fabric-ca-client /usr/local/bin/fabric-ca-client && \
    chmod +x /usr/local/bin/fabric-ca-client && \
    rm -rf /tmp/fabric-ca.tar.gz /tmp/bin /tmp/config

COPY package.json .

RUN npm install --omit=dev

COPY src ./src

COPY entrypoint.sh .
COPY register-vnf.sh .
COPY enroll-vnf.sh .

RUN chmod +x \
    /opt/vnf/entrypoint.sh \
    /opt/vnf/register-vnf.sh \
    /opt/vnf/enroll-vnf.sh

ENTRYPOINT ["/opt/vnf/entrypoint.sh"]