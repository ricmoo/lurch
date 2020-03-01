"use strict";

const fs = require("fs");

const { ethers } = require("ethers");
const { solc } = require("@ethersproject/cli");

const lurchAddress = "0x716C860ACbC070CB753A37e054a041ace4F04d67";

const lurchAbi = [
    "function eval(bytes bytecode, bytes calldata) returns (string)"
];

const provider = new ethers.providers.JsonRpcProvider();
const signer = provider.getSigner();

const lurchContract = new ethers.Contract(lurchAddress, lurchAbi, signer);

(async function() {
    const erc20Code = solc.compile(fs.readFileSync("simple-erc20.sol").toString(), {
        optimize: true
    }).filter((c) => (c.name === "Token"))[0];
    //console.log(erc20Code, erc20Code.interface.encodeFunctionData("symbol"));

    const erc20Contract = new ethers.Contract("0x9B5e90BE432fBa8fBADeb31698d107A1602e0C21", erc20Code.interface, signer);

    /*
    const factory = new ethers.ContractFactory(erc20Code.interface, erc20Code.bytecode, signer);
    {
        const contract = await factory.deploy();
        await contract.deployed();
        console.log(contract);
    }
    return;
    */

    /*
    // This needs to be done once to set up the cntract in Lurch's storage
    const tx = await lurchContract.eval(
        erc20Code.bytecode,
        "0x"
    );
    const receipt = await tx.wait();
    console.log(receipt.logs);
    return;
    */

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
    console.log("symbol() =>", symbol);
    console.log("symbol() lurch cost:", symbolCost.toString());
    console.log("symbol() vanilla cost:", symbolVanillaCost.toString());

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
    console.log("name() =>", name);
    console.log("name() cost:", nameCost.toString());
    console.log("name() vanilla cost:", nameVanillaCost.toString());

    //const otherAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const otherAddress = lurchAddress; //ethers.utils.hexlify(ethers.utils.randomBytes(20));

    const transferTx = await lurchContract.eval(
        erc20Code.runtime,
        erc20Code.interface.encodeFunctionData("transfer", [ otherAddress, 1 ])
    );
    const transferReceipt = await transferTx.wait();
    //console.log(transferReceipt);
    const transferVanillaTx = await erc20Contract.transfer(otherAddress, 100);
    const transferVanillaReceipt = await transferVanillaTx.wait();
    //console.log("transfer()", );
    console.log("transfer() lurch cost:", transferReceipt.gasUsed.toString());
    console.log("transfer() vanilla cost:", transferVanillaReceipt.gasUsed.toString());

})().catch((error) => {
    console.log(error);
});
