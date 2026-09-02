const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const grpc = require("@grpc/grpc-js");
const {
    connect,
    signers,
    hash
} = require("@hyperledger/fabric-gateway");

const VNF_ID = process.env.VNF_ID;
const GNB_ID = process.env.GNB_ID;

const FABRIC_PEER =
    process.env.FABRIC_PEER;

const FABRIC_PEER_IP =
    process.env.FABRIC_PEER_IP;

const FABRIC_CHANNEL =
    process.env.FABRIC_CHANNEL;

const FABRIC_CHAINCODE =
    process.env.FABRIC_CHAINCODE || "logging";

const VNF_STATE_DIR =
    process.env.VNF_STATE_DIR || "/opt/vnf-state";

const LOG_FILE =
    process.env.GNB_LOG_FILE || "/mnt/gnb-logs/gnb.log";

const MSP_ID =
    process.env.FABRIC_MSP_ID || "Org1MSP";

const PEER_PORT = 7051;

const CONNECT_TIMEOUT_MS =
    Number(process.env.FABRIC_CONNECT_TIMEOUT_MS || 5000);

const CONNECT_RETRY_MS =
    Number(process.env.FABRIC_CONNECT_RETRY_MS || 3000);

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function getCertificate() {
    const certificatePath = path.join(
        VNF_STATE_DIR,
        "msp",
        "signcerts",
        "cert.pem"
    );

    return fs.readFileSync(certificatePath);
}

function getPrivateKey() {
    const keystorePath = path.join(
        VNF_STATE_DIR,
        "msp",
        "keystore"
    );

    const files = fs.readdirSync(keystorePath);

    const keyFile = files.find(
        file => file.endsWith("_sk")
    );

    if (!keyFile) {
        throw new Error(
            `No private key found in ${keystorePath}`
        );
    }

    const keyPath = path.join(
        keystorePath,
        keyFile
    );

    return crypto.createPrivateKey({
        key: fs.readFileSync(keyPath),
        format: "pem"
    });
}

function getTlsRootCertificate() {
    const cacertsPath = path.join(
        VNF_STATE_DIR,
        "msp",
        "cacerts"
    );

    const files = fs.readdirSync(cacertsPath);

    const certificateFile = files.find(
        file => file.endsWith(".pem")
    );

    if (!certificateFile) {
        throw new Error(
            `No CA certificate found in ${cacertsPath}`
        );
    }

    return fs.readFileSync(
        path.join(cacertsPath, certificateFile)
    );
}

function getPeerEndpoint() {
    if (FABRIC_PEER_IP) {
        return `${FABRIC_PEER_IP}:${PEER_PORT}`;
    }

    return `${FABRIC_PEER}:${PEER_PORT}`;
}

function getPeerTlsAuthority() {
    /*
     * The peer certificate is issued with the peer hostname
     * and IP as SANs. The hostname is therefore preferred for
     * TLS authority validation.
     */
    return FABRIC_PEER || FABRIC_PEER_IP;
}

function createGrpcClient() {
    const tlsRootCertificate =
        getTlsRootCertificate();

    const peerEndpoint =
        getPeerEndpoint();

    const authority =
        getPeerTlsAuthority();

    console.log(
        `Fabric peer endpoint: ${peerEndpoint}`
    );

    console.log(
        `Fabric TLS authority: ${authority}`
    );

    return new grpc.Client(
        peerEndpoint,
        grpc.credentials.createSsl(
            tlsRootCertificate
        ),
        {
            "grpc.ssl_target_name_override": authority
        }
    );
}

function createGateway() {
    const certificate =
        getCertificate();

    const privateKey =
        getPrivateKey();

    const identity = {
        mspId: MSP_ID,
        credentials: certificate
    };

    const signer =
        signers.newPrivateKeySigner(
            privateKey
        );

    const client =
        createGrpcClient();

    const gateway =
        connect({
            client,
            identity,
            signer,
            hash: hash.sha256
        });

    return {
        gateway,
        client
    };
}

function parseLogLine(line) {
    const match = line.match(
        /^\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+(.*)$/
    );

    if (!match) {
        return null;
    }

    return {
        timestamp: match[1],
        component: match[2],
        level: match[3],
        message: match[4]
    };
}

function createLogRecord(line) {
    const parsed =
        parseLogLine(line);

    if (!parsed) {
        return null;
    }

    return {
        vnfId: VNF_ID,
        gnbId: GNB_ID,
        timestamp: parsed.timestamp,
        component: parsed.component,
        level: parsed.level,
        message: parsed.message
    };
}

async function submitLog(contract, record) {
    const payload =
        JSON.stringify(record);

    console.log(
        `Submitting ${record.level} ${record.component} log`
    );

    const result =
        await contract.submitTransaction(
            "StoreLog",
            payload
        );

    console.log(
        `Committed log for ${record.gnbId}`
    );

    if (result && result.length > 0) {
        console.log(
            `Chaincode response: ${Buffer.from(result).toString("utf8")}`
        );
    }
}

async function processLogLine(contract, line) {
    const record =
        createLogRecord(line);

    if (!record) {
        console.log(
            `Ignoring unrecognised log line: ${line}`
        );
        return;
    }

    try {
        await submitLog(
            contract,
            record
        );
    } catch (error) {
        console.error(
            `Failed to commit log: ${error.message}`
        );
    }
}

async function followLogFile(contract) {
    console.log(
        `Following: ${LOG_FILE}`
    );

    let position = 0;
    let buffer = "";

    while (true) {

        try {

            const stats =
                fs.statSync(LOG_FILE);

            if (stats.size < position) {
                position = 0;
                buffer = "";
            }

            if (stats.size > position) {

                const fd =
                    fs.openSync(
                        LOG_FILE,
                        "r"
                    );

                const bytesToRead =
                    stats.size - position;

                const data =
                    Buffer.alloc(
                        bytesToRead
                    );

                fs.readSync(
                    fd,
                    data,
                    0,
                    bytesToRead,
                    position
                );

                fs.closeSync(fd);

                position =
                    stats.size;

                buffer +=
                    data.toString();

                const lines =
                    buffer.split("\n");

                buffer =
                    lines.pop();

                for (const line of lines) {

                    const trimmed =
                        line.trim();

                    if (!trimmed) {
                        continue;
                    }

                    await processLogLine(
                        contract,
                        trimmed
                    );
                }
            }

        } catch (error) {

            console.error(
                `Log reader error: ${error.message}`
            );
        }

        await sleep(1000);
    }
}

async function waitForFabric() {

    while (true) {

        let gateway = null;
        let client = null;

        try {

            console.log(
                "Connecting to Fabric Gateway..."
            );

            ({
                gateway,
                client
            } = createGateway());

            const network =
                gateway.getNetwork(
                    FABRIC_CHANNEL
                );

            const contract =
                network.getContract(
                    FABRIC_CHAINCODE
                );

            /*
             * Evaluate a harmless transaction query.
             *
             * This proves that:
             *   - TLS works
             *   - the VNF certificate works
             *   - the peer is reachable
             *   - the channel exists
             *   - the chaincode is committed
             */
            try {
                await contract.evaluateTransaction(
                    "LogExists",
                    "__vnf_startup_probe__"
                );
            } catch (error) {

                /*
                 * LogExists returning false is expected.
                 * Other errors indicate the Fabric path
                 * is not ready yet.
                 */
                if (
                    !error.message.includes(
                        "does not exist"
                    )
                ) {
                    throw error;
                }
            }

            console.log(
                "Fabric Gateway connected."
            );

            return {
                gateway,
                client,
                contract
            };

        } catch (error) {

            if (gateway) {
                try {
                    gateway.close();
                } catch (_) {}
            }

            if (client) {
                try {
                    client.close();
                } catch (_) {}
            }

            console.error(
                `Fabric not ready: ${error.message}`
            );

            console.log(
                `Retrying in ${CONNECT_RETRY_MS}ms...`
            );

            await sleep(
                CONNECT_RETRY_MS
            );
        }
    }
}

async function main() {

    console.log(
        "=============================================="
    );

    console.log(
        " VNF application"
    );

    console.log(
        "=============================================="
    );

    console.log(
        `VNF ID       : ${VNF_ID}`
    );

    console.log(
        `gNB ID       : ${GNB_ID}`
    );

    console.log(
        `Fabric Peer  : ${FABRIC_PEER}`
    );

    console.log(
        `Peer IP      : ${FABRIC_PEER_IP}`
    );

    console.log(
        `Channel      : ${FABRIC_CHANNEL}`
    );

    console.log(
        `Chaincode    : ${FABRIC_CHAINCODE}`
    );

    console.log("");

    if (!VNF_ID) {
        throw new Error(
            "VNF_ID is required"
        );
    }

    if (!FABRIC_PEER) {
        throw new Error(
            "FABRIC_PEER is required"
        );
    }

    if (!FABRIC_CHANNEL) {
        throw new Error(
            "FABRIC_CHANNEL is required"
        );
    }

    if (!fs.existsSync(LOG_FILE)) {
        throw new Error(
            `Log file does not exist: ${LOG_FILE}`
        );
    }

    const {
        gateway,
        client,
        contract
    } = await waitForFabric();

    const shutdown = () => {

        try {
            gateway.close();
        } catch (_) {}

        try {
            client.close();
        } catch (_) {}

        process.exit(0);
    };

    process.once(
        "SIGTERM",
        shutdown
    );

    process.once(
        "SIGINT",
        shutdown
    );

    await followLogFile(
        contract
    );
}

main().catch(error => {

    console.error(
        error
    );

    process.exit(1);
});