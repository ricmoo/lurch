"use strict";

const { ethers } = require("ethers");

const springboardAddress = "0xBeB7bBd8A0fd98ec06353ec849BCcD84666040BC";

const bytecode = "0x608060405260405161034e38038061034e8339818101604052602081101561002657600080fd5b8101908080519060200190929190505050336000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550806001819055506000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff167f95b18bbe5373dcbe675d3ab2ae6e3888392575c51b8b8c9c3cbbdb431af1929960015434604051808381526020018281526020019250505060405180910390a250610247806101076000396000f3fe608060405234801561001057600080fd5b506004361061004c5760003560e01c806335f46994146100515780633fa4f2451461005b57806355241077146100795780638da5cb5b146100a7575b600080fd5b6100596100f1565b005b610063610184565b6040518082815260200191505060405180910390f35b6100a56004803603602081101561008f57600080fd5b810190808035906020019092919050505061018a565b005b6100af6101ec565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161461014a57600080fd5b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16ff5b60015481565b3373ffffffffffffffffffffffffffffffffffffffff167fe435f0fbe584e62b62f48f4016a57ef6c95e4c79f5babbe6ad3bb64f3281d26160015483604051808381526020018281526020019250505060405180910390a28060018190555050565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff168156fea264697066735822122011bddfc1f860f9dd05ec5d8c245c4a342bcf9b789ee2b44bed8eef254b92b31d64736f6c63430006010033";
const abi = [
    "constructor(uint256 _value) payable",
    "function owner() view returns (address)",
    "function value() view returns (uint256)",
    "function setValue(uint256 _value)",
    "function die()",
    "event Created(address indexed owner, uint256 value, uint256 endowment)",
    "event ValueChanged(address indexed author, uint256 oldValue, uint256 newValue)",
    "event Deployed(address indexed deployer, address created)"
];
const iface = new ethers.utils.Interface(abi);

function getDeploy(value) {
    return {
        to: springboardAddress,
        data: ethers.utils.concat([
            bytecode,
            iface.encodeDeploy([ value ])
        ])
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
        const txSent = await signer.sendTransaction(getDeploy(42));
        const receipt = await txSent.wait();
        const log = iface.parseLog(receipt.logs.pop());
        const contract = new ethers.Contract(log.args[1], iface, signer);
        console.log("Owner:", await contract.owner())
        console.log("Value(42):", await contract.value())
        await contract.setValue(12);
        console.log("Value(12):", await contract.value())
        await contract.die()
    }

    {
        const txSent = await signer.sendTransaction(getDeploy(43));
        const receipt = await txSent.wait();
        const log = iface.parseLog(receipt.logs.pop());
        const contract = new ethers.Contract(log.args[1], iface, signer);
        console.log("Owner:", await contract.owner())
        console.log("Value(43):", await contract.value())
        await contract.setValue(12);
        console.log("Value(12):", await contract.value())
        await contract.die()
    }

})();
