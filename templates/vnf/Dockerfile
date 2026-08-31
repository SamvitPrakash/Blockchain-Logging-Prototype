FROM python:3.12-slim AS python-base

FROM hyperledger/fabric-ca:1.5.17 AS fabric-ca

FROM python-base

WORKDIR /opt/vnf

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fabric-ca /usr/local/bin/fabric-ca-client /usr/local/bin/fabric-ca-client

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY register-vnf.sh /opt/vnf/register-vnf.sh
COPY enroll-vnf.sh /opt/vnf/enroll-vnf.sh
COPY entrypoint.sh /opt/vnf/entrypoint.sh

COPY src ./src

RUN chmod +x \
    /opt/vnf/register-vnf.sh \
    /opt/vnf/enroll-vnf.sh \
    /opt/vnf/entrypoint.sh

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/opt/vnf/entrypoint.sh"]