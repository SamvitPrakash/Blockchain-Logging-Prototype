'use strict';

const { Contract } = require('fabric-contract-api');

class LoggingContract extends Contract {

    async StoreLog(ctx, ...args) {
        if (args.length === 0) {
            throw new Error('StoreLog requires log data');
        }

        const txId = ctx.stub.getTxID();

        const record = {
            txId,
            timestamp: new Date().toISOString(),
            args
        };

        await ctx.stub.putState(
            txId,
            Buffer.from(JSON.stringify(record))
        );

        return JSON.stringify(record);
    }

    async GetLog(ctx, txId) {
        const data = await ctx.stub.getState(txId);

        if (!data || data.length === 0) {
            throw new Error(`Log ${txId} does not exist`);
        }

        return data.toString();
    }

    async LogExists(ctx, txId) {
        const data = await ctx.stub.getState(txId);
        return data && data.length > 0;
    }
}

module.exports = {
    LoggingContract
};