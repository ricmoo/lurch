"use strict";

const fs = require("fs");

const { ethers } = require("ethers");
//const { assemble, parse } = require("@ethersproject/asm");
const { assemble, disassemble, formatBytecode, parse } = require("/Users/ricmoo/Development/ethers/ethers.js-v5/packages/asm");
//const { assemble, disassemble, formatBytecode, parse } = require("@ethersproject/asm");

const provider = new ethers.providers.JsonRpcProvider();
provider.pollingInterval = 100;
const signer = provider.getSigner();

// @TODO: Return (uint status, bytes result)
// Status: 0 => revert, 1 => success, 2 => debug state
const ABI = [
    "function eval(bytes bytecode, bytes calldata) view returns (uint)"
];

async function getBytecode(filename, target) {
    const source = fs.readFileSync(filename).toString();
    try {
        const ast = parse(source);
        //console.dir(ast, { depth: null });
        const bytecode = await assemble(ast, { target: target });
        console.log(`Bytecode (${ filename }): ${ bytecode }`);
        return bytecode;
    } catch (error) {
        console.log(error);
        (error.errors || []).forEach((error) => {
            consl.e.log(error);
        });
        throw error;
    }
}

async function deploy() {
    const lurchBytecode = await getBytecode("./lurch.asm");
    const lurchRuntimeBytecode = await getBytecode("./lurch.asm", "lurch");
    console.log(formatBytecode(disassemble(lurchRuntimeBytecode)));

    const tx = await signer.sendTransaction({
        data: lurchBytecode
    });

    //console.log("Deploy Tx", tx);
    const receipt = await tx.wait();
    //console.log("Deploy Receipt", receipt);

    return receipt.contractAddress;

}

(async function() {

    const contractAddress = await deploy();

    const contract = new ethers.Contract(contractAddress, ABI, provider);

    const testBytecode = await getBytecode("./test.asm");
    const tx = await contract.populateTransaction.eval(testBytecode, "0x1234");

    const result = ethers.utils.arrayify(await provider.call(tx));

    for (let i = 0; i < result.length; i += 32) {
        console.log(ethers.utils.hexlify(result.slice(i, i + 32)));
    }
})();
