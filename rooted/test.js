"use strict";

const fs = require("fs");

const { ethers } = require("ethers");
const { assemble, disassemble, formatBytecode, parse } = require("/Users/ricmoo/Development/ethers/ethers.js-v5/packages/asm");
//const { assemble, disassemble, formatBytecode, parse } = require("@ethersproject/asm");

const provider = new ethers.providers.JsonRpcProvider();
provider.pollingInterval = 100;
const signer = provider.getSigner();

const sampleBytecode = "0x608060405234801561001057600080fd5b50336000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550602a6001819055506101cf806100686000396000f3fe608060405234801561001057600080fd5b506004361061004c5760003560e01c806335f46994146100515780633fa4f2451461005b57806355241077146100795780638da5cb5b146100a7575b600080fd5b6100596100f1565b005b610063610164565b6040518082815260200191505060405180910390f35b6100a56004803603602081101561008f57600080fd5b810190808035906020019092919050505061016a565b005b6100af610174565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161461014a57600080fd5b600073ffffffffffffffffffffffffffffffffffffffff16ff5b60015481565b8060018190555050565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff168156fea26469706673582212202630d7b4fc9c733475a2917b5476d132a91b3f98e08610e6a3ddbf71fa4520c464736f6c63430006010033";

const ABI = [
    "constructor()",
    "function setValue(uint256 _value)",
    "function value() view returns (uint256)",
    "function owner() view returns (address)",
    "function die()"
];

async function getBytecode(filename, options) {
    const source = fs.readFileSync(filename).toString();
    try {
        const ast = parse(source);
        //console.dir(ast, { depth: null });
        const bytecode = await assemble(ast, options);
        console.log(`Bytecode (${ filename }): ${ bytecode }`);
        return bytecode;
    } catch (error) {
        console.log(error);
        (error.errors || []).forEach((error) => {
            console.log(error);
        });
        throw error;
    }
}

async function deploy(filename, target, options) {
    if (options == null) { options = { }; }
    console.log("Deploying:", filename);

    const bytecode = await getBytecode(filename, options);

    if (target) { options.target = target; }
    const runtimeBytecode = await getBytecode(filename, options);

    //console.log(formatBytecode(disassemble(runtimeBytecode)));
    console.log("Runtime:", runtimeBytecode);
    console.log("Rooted Size:", ethers.utils.hexDataLength(runtimeBytecode));

    const tx = await signer.sendTransaction({
        data: bytecode
    });

    //console.log("Deploy Tx", tx);
    const receipt = await tx.wait();
    //console.log("Deploy Receipt", receipt);

    console.log("Deployment Gas Used:", receipt.gasUsed.toString());

    return receipt.contractAddress;

}

(async function() {

    const lurchAddress = await deploy("lurch-bare.asm", "lurch");
    console.log("Lurch Address:", lurchAddress);
    if (false) {
        const tx0 = await signer.sendTransaction({
            to: lurchAddress,
            data: ethers.utils.hexlify(ethers.utils.concat([
                ethers.constants.HashZero,
                ethers.utils.zeroPad("0x05", 32),
                "0x600a6000f3"
            ]))
        });
        const receipt = await tx0.wait();
        console.log(receipt.logs);
    }

    const springboardAddress = await deploy("Springboard.asm", "Springboard", {
        defines: {
            LurchAddress: lurchAddress
        }
    });
    console.log("Springboard Address:", springboardAddress);

    const tx = {
        to: springboardAddress,
        data: sampleBytecode
    };

    const txSent = await signer.sendTransaction(tx);
    const receipt = await txSent.wait();
    console.log(receipt.logs);

})();

