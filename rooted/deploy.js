"use strict";

const fs = require("fs");

const { ethers } = require("ethers");
const { assemble, disassemble, formatBytecode, parse } = require("@ethersproject/asm");

//const provider = new ethers.providers.JsonRpcProvider();
//provider.pollingInterval = 100;
//const signer = provider.getSigner();

const signer = accounts[0];

async function getBytecode(filename, options) {
    const source = fs.readFileSync(filename).toString();
    try {
        const ast = parse(source);
        //console.dir(ast, { depth: null });
        const bytecode = await assemble(ast, options);
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
    console.log(`Deploy Bytecode (${ filename }): ${ bytecode }`);

    if (target) { options.target = target; }
    const runtimeBytecode = await getBytecode(filename, options);

    //console.log(formatBytecode(disassemble(runtimeBytecode)));
    console.log("Runtime:", runtimeBytecode);
    console.log("Size:", ethers.utils.hexDataLength(runtimeBytecode));

    const tx = await signer.sendTransaction({
        data: bytecode
    });

    const receipt = await tx.wait();

    console.log("Deployment Gas Used:", receipt.gasUsed.toString());

    return receipt.contractAddress;
}

(async function() {
    const network = await provider.getNetwork();

    //const dataAddress = await deploy("storage.asm", "Storage");
    //console.log("Data Address:", dataAddress);

    const lurchAddress = await deploy("lurch-rooted.asm", "Lurch");
    console.log("Lurch Address:", lurchAddress);

    const springboardAddress = await deploy("springboard-rooted.asm", "Springboard", {
        defines: {
            Network: network.name,
            LurchAddress: lurchAddress
        }
    });
    console.log("Springboard Address:", springboardAddress);

})();

