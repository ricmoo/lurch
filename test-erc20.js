"use strict";

const fs = require("fs");

const { ethers } = require("ethers");
const { assemble, disassemble, formatBytecode, parse } = require("/Users/ricmoo/Development/ethers/ethers.js-v5/packages/asm");
const { solc } = require("@ethersproject/cli");

const provider = new ethers.providers.JsonRpcProvider();
provider.pollingInterval = 100;
const signer = provider.getSigner();


async function getBytecode(filename, target) {
    const source = fs.readFileSync(filename).toString();
    try {
        const ast = parse(source);
        const bytecode = await assemble(ast, { target: target });
        //console.log(`Bytecode (${ filename }): ${ bytecode }`);
        return bytecode;
    } catch (error) {
        console.log(error);
        (error.errors || []).forEach((error) => {
            consl.e.log(error);
        });
        throw error;
    }
}

async function deployLurch() {
    const lurchBytecode = await getBytecode("./lurch.asm");
    //console.log("DEPLOY", lurchBytecode);
    //const lurchRuntimeBytecode = await getBytecode("./lurch.asm", "lurch");
    //console.log(formatBytecode(disassemble(lurchRuntimeBytecode)));
    //console.log("Lurch Size:", ethers.utils.hexDataLength(lurchRuntimeBytecode));

    const tx = await signer.sendTransaction({
        data: lurchBytecode
    });
    const receipt = await tx.wait();

    //console.log("Deployment Gas Used:", receipt.gasUsed.toString());

    return receipt.contractAddress;
}

function computeIntrinsic(data) {
    let result = 0;
    data = ethers.utils.arrayify(data);
    for (let i = 0; i < data.length; i++) {
        if (data[i]) {
            result += 68;
        } else {
            result += 4;
        }
    }
    return result;
}

(async function() {
    console.log("Deploying new Lurch instance...");
    const lurchAddress = await deployLurch();

    const lurchContract = new ethers.Contract(lurchAddress, [
        "function eval(bytes bytecode, bytes calldata) returns (string)"
    ], signer);

    const lurchContractAddr = new ethers.Contract(lurchAddress, [
        "function eval(bytes bytecode, bytes calldata) returns (address)"
    ], signer);

    const lurchContractUint = new ethers.Contract(lurchAddress, [
        "function eval(bytes bytecode, bytes calldata) returns (uint256)"
    ], signer);


    const erc20Code = solc.compile(fs.readFileSync("simple-erc20.sol").toString(), {
        optimize: true
    }).filter((c) => (c.name === "Token"))[0];
    //console.log(erc20Code, erc20Code.interface.encodeFunctionData("symbol"));

    //const erc20Contract = new ethers.Contract("0x9B5e90BE432fBa8fBADeb31698d107A1602e0C21", erc20Code.interface, signer);

    console.log("Deploying vanilla ERC-20 contract...");
    const factory = new ethers.ContractFactory(erc20Code.interface, erc20Code.bytecode, signer);
    const erc20Contract = await factory.deploy();
    await erc20Contract.deployed();
    //console.log(contract);

    // Make sure the constructor of the ERC-20 contract gets run in the Lurch instance
    console.log("Running ERC-20 constructor in Lurch...");
    const tx = await lurchContract.eval(erc20Code.bytecode, "0x");
    await tx.wait();

    console.log("");
    {
        const symbol = await lurchContract.callStatic.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("symbol")
        );
        const symbolCost = await lurchContract.estimate.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("symbol")
        );
        const symbolVanillaTx = await erc20Contract.populateTransaction.symbol();
        const symbolVanillaCost = await provider.estimateGas(symbolVanillaTx);
        console.log(`symbol():              ${ symbol }`);
        console.log(`symbol() lurch cost:   ${ symbolCost.toString() }`);
        console.log(`symbol() vanilla cost: ${ symbolVanillaCost.toString() }`);
        console.log(`Non-Intrinsic Delta:   ${ symbolCost.sub(21000).sub(computeIntrinsic(symbolVanillaTx.data)).toNumber() / symbolVanillaCost.sub(21000).toNumber() }x`);
    }


    console.log("");
    {
        const name = await lurchContract.callStatic.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("name")
        );
        const nameCost = await lurchContract.estimate.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("name")
        );

        const nameVanillaTx = await erc20Contract.populateTransaction.name();
        const nameVanillaCost = await provider.estimateGas(nameVanillaTx);
        console.log(`name():              ${ name }`);
        console.log(`name() Lurch cost:   ${ nameCost.toString() }`);
        console.log(`name() vanilla cost: ${ nameVanillaCost.toString() }`);
        console.log(`Non-Intrinsic Delta: ${ nameCost.sub(21000).sub(computeIntrinsic(nameVanillaTx.data)).toNumber() / nameVanillaCost.sub(21000).toNumber() }x`);
    }

    console.log("");
    let owner = null;
    {
        owner = await lurchContractAddr.callStatic.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("owner")
        );

        const ownerCost = await lurchContractAddr.estimate.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("owner")
        );

        const ownerVanillaTx = await erc20Contract.populateTransaction.owner();
        const ownerVanillaCost = await provider.estimateGas(ownerVanillaTx);
        console.log(`owner():              ${ owner }`);
        console.log(`owner() Lurch cost:   ${ ownerCost.toString() }`);
        console.log(`owner() vanilla cost: ${ ownerVanillaCost.toString() }`);
        console.log(`Non-Intrinsic Delta: ${ ownerCost.sub(21000).sub(computeIntrinsic(ownerVanillaTx.data)).toNumber() / ownerVanillaCost.sub(21000).toNumber() }x`);
    }

    console.log("");
    {
        const balance = await lurchContractUint.callStatic.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("balanceOf", [ owner ])
        );
        const balanceCost = await lurchContractUint.estimate.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("balanceOf", [ owner ])
        );

        const balanceVanillaTx = await erc20Contract.populateTransaction.balanceOf(owner);
        const balanceVanillaCost = await provider.estimateGas(balanceVanillaTx);
        console.log(`balanceOf(${ owner }):              ${ balance.toString() }`);
        console.log(`balanceOf(${ owner }) Lurch cost:   ${ balanceCost.toString() }`);
        console.log(`balanceOf(${ owner }) vanilla cost: ${ balanceVanillaCost.toString() }`);
        console.log(`Non-Intrinsic Delta: ${ balanceCost.sub(21000).sub(computeIntrinsic(balanceVanillaTx.data)).toNumber() / balanceVanillaCost.sub(21000).toNumber() }x`);
    }

    console.log("");
    {
        //const otherAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
        const otherAddress = "0xaB7C8803962c0f2F5BBBe3FA8bf41cd82AA1923C";
        const transferTx = await lurchContract.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("transfer", [ otherAddress, 42 ])
        );

        const transferReceipt = await transferTx.wait();
        const transferVanillaTx = await erc20Contract.transfer(otherAddress, 42);
        const transferVanillaReceipt = await transferVanillaTx.wait();
        console.log(`transfer(${ otherAddress }, 42)  Lurch cost:   ${ transferReceipt.gasUsed.toString() }`);
        console.log(`transfer(${ otherAddress }, 42)) vanilla cost: ${ transferVanillaReceipt.gasUsed.toString() }`);
        console.log(`Non-Intrinsic Delta: ${ transferReceipt.gasUsed.sub(21000).sub(computeIntrinsic(transferTx.data)).toNumber() / transferVanillaReceipt.gasUsed.sub(21000).toNumber() }x`);
    }

    console.log("");
    {
        const balance = await lurchContractUint.callStatic.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("balanceOf", [ owner ])
        );
        const balanceCost = await lurchContractUint.estimate.eval(
            erc20Code.runtime,
            erc20Code.interface.encodeFunctionData("balanceOf", [ owner ])
        );

        const balanceVanillaTx = await erc20Contract.populateTransaction.balanceOf(owner);
        const balanceVanillaCost = await provider.estimateGas(balanceVanillaTx);
        console.log(`balanceOf(${ owner }):              ${ balance.toString() }`);
        console.log(`balanceOf(${ owner }) Lurch cost:   ${ balanceCost.toString() }`);
        console.log(`balanceOf(${ owner }) vanilla cost: ${ balanceVanillaCost.toString() }`);
        console.log(`Non-Intrinsic Delta: ${ balanceCost.sub(21000).sub(computeIntrinsic(balanceVanillaTx.data)).toNumber() / balanceVanillaCost.sub(21000).toNumber() }x`);
    }

})().catch((error) => {
    console.log(error);
});
