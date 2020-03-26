"use strict";

const { ethers } = require("ethers");

const springboardAddress = "0x26C94A92545f93ec82fe8695806A10A4C96244E5";

const bytecode = "0x608060405260405161037c38038061037c8339818101604052602081101561002657600080fd5b5051600080546001600160a01b03191633179081905560018290556040805183815234602082015281516001600160a01b0393909316927f95b18bbe5373dcbe675d3ab2ae6e3888392575c51b8b8c9c3cbbdb431af19299929181900390910190a2506102e4806100986000396000f3fe608060405234801561001057600080fd5b50600436106100625760003560e01c80631facc6e51461006757806335f46994146100865780633fa4f2451461008e578063426500f2146100a857806355241077146100b05780638da5cb5b146100cd575b600080fd5b6100846004803603602081101561007d57600080fd5b50356100f1565b005b6100846101a5565b6100966101ca565b60408051918252519081900360200190f35b6100966101d0565b610084600480360360208110156100c657600080fd5b503561025c565b6100d561029f565b604080516001600160a01b039092168252519081900360200190f35b337fd2aa6695cf3da956f330d79de1849760475b344347c33dad2db825ab082d6a6561011b6101d0565b60408051918252602082018590528051918290030190a260408051631ab06ee560e01b815260006004820181905260248201849052915173ac180e659db90529b3a1890e9f113c6859bf4b1992631ab06ee5926044808201939182900301818387803b15801561018a57600080fd5b505af115801561019e573d6000803e3d6000fd5b5050505050565b6000546001600160a01b031633146101bc57600080fd5b6000546001600160a01b0316ff5b60015481565b600073ac180e659db90529b3a1890e9f113c6859bf4b196001600160a01b0316639507d39a60006040518263ffffffff1660e01b81526004018082815260200191505060206040518083038186803b15801561022b57600080fd5b505afa15801561023f573d6000803e3d6000fd5b505050506040513d602081101561025557600080fd5b5051905090565b6001546040805191825260208201839052805133927fe435f0fbe584e62b62f48f4016a57ef6c95e4c79f5babbe6ad3bb64f3281d26192908290030190a2600155565b6000546001600160a01b03168156fea2646970667358221220031eaaba5508588a42fd8ffedf23e4edaf7e2aa713ecc9179c9928819d6e099364736f6c63430006010033";

const abi = [
    "constructor(uint256 _value) payable",
    "function owner() view returns (address)",
    "function value() view returns (uint256)",
    "function setValue(uint256 _value)",
    "function persistentValue() view returns (uint256)",
    "function setPersistentValue(uint256 _value)",
    "function die()",
    "event Created(address indexed owner, uint256 value, uint256 endowment)",
    "event ValueChanged(address indexed author, uint256 oldValue, uint256 newValue)",
    "event Deployed(address indexed deployer, address created)"
];
const iface = new ethers.utils.Interface(abi);

function getDeploy(value, endowment) {
    return {
        to: springboardAddress,
        data: ethers.utils.concat([
            bytecode,
            iface.encodeDeploy([ value ])
        ]),
        value: (endowment || 0)
    }
}

async function getAddress(signer) {
    const code = await signer.provider.getCode(springboardAddress);
    const sender = await signer.getAddress();

    const codeBytes = ethers.utils.arrayify(code);
    const length = codeBytes.length;

    const bsSize = (codeBytes[length - 3] << 8) | codeBytes[length - 2];
    const bsOffset = (codeBytes[length - 5] << 8) | codeBytes[length - 4];

    const address = ethers.utils.getCreate2Address(
        springboardAddress,
        ethers.utils.zeroPad(sender, 32),
        ethers.utils.keccak256(codeBytes.slice(bsOffset, bsOffset + bsSize))
    )

    return address;
}

(async function() {
    const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545");
    const signer = provider.getSigner();

    const contractAddress = "0x1425779817b881658ba7504045dfc5d047ac2d74";
    const code = await provider.getCode(contractAddress);

    console.log("Created Address:", await getAddress(signer));

    if (code !== "0x") {
        const contract = new ethers.Contract(contractAddress, iface, signer);
        const tx = await contract.die();
        const receipt = await tx.wait();
    }

    {
        const tx = getDeploy(42);
        delete tx.to;
        const txSent = await signer.sendTransaction(tx);
        const receipt = await txSent.wait();
        console.log("Gas Used (traditional):", receipt.gasUsed.toString());
    }

    {
        console.log("Deployment #1");

        const txSent = await signer.sendTransaction(getDeploy(42, 42));
        const receipt = await txSent.wait();
        console.log(receipt.logs);
        console.log("Gas Used (rooted.eth):", receipt.gasUsed.toString());
        const log = iface.parseLog(receipt.logs.pop());
        const contract = new ethers.Contract(log.args[1], iface, signer);
        console.log("Owner:", await contract.owner())
        console.log("PersistentValue(last):", await contract.persistentValue())
        console.log("Value(42):", await contract.value())
        let txWait = await contract.setPersistentValue(11);
        await txWait.wait()
        txWait = await contract.setValue(12);
        await txWait.wait()
        console.log("PersistentValue(11):", await contract.persistentValue())
        console.log("Value(12):", await contract.value())
        txWait = await contract.die()
        await txWait.wait()
    }

    {
        console.log("Deployment #2");

        const txSent = await signer.sendTransaction(getDeploy(43, 0));
        const receipt = await txSent.wait();
        console.log(receipt.logs);
        const log = iface.parseLog(receipt.logs.pop());
        const contract = new ethers.Contract(log.args[1], iface, signer);
        console.log("Owner:", await contract.owner())
        console.log("PersistentValue(11):", await contract.persistentValue())
        console.log("Value(43):", await contract.value())
        let txWait = await contract.setPersistentValue(1);
        await txWait.wait()
        txWait = await contract.setValue(12);
        await txWait.wait();
        console.log("Value(12):", await contract.value())
        txWait = await contract.die()
        await txWait.wait();
    }

})();
