'use strict';

const { Contract } = require('fabric-contract-api');

class LoggingContract extends Contract {

    async StoreLog(ctx, payload) {
        if (payload === undefined || payload === null || payload === '') {
            throw new Error('StoreLog requires a payload');
        }

        const transactionId = ctx.stub.getTxID();

        const record = {
            transactionId,
            payload
        };

        await ctx.stub.putState(
            transactionId,
            Buffer.from(JSON.stringify(record))
        );

        return transactionId;
    }

    async GetLog(ctx, transactionId) {
        if (!transactionId) {
            throw new Error('transactionId is required');
        }

        const data = await ctx.stub.getState(transactionId);

        if (!data || data.length === 0) {
            throw new Error(
                `Log ${transactionId} does not exist`
            );
        }

        return data.toString();
    }

    async GetAllLogs(ctx) {
        const iterator = await ctx.stub.getStateByRange('', '');
        const logs = [];

        try {
            while (true) {
                const result = await iterator.next();

                if (result.value && result.value.value) {
                    logs.push(
                        JSON.parse(
                            result.value.value.toString('utf8')
                        )
                    );
                }

                if (result.done) {
                    break;
                }
            }
        } finally {
            await iterator.close();
        }

        return JSON.stringify(logs);
    }
}

module.exports = {
    contracts: [
        LoggingContract
    ]
};