"use strict";

const { ethers } = require("ethers");
const { solc } = require("@ethersproject/cli");

let compile = null;

module.exports.solcVersion = (function() {
    try {
        const _solc = (solc.customRequire("."))("solc");
        compile = solc.wrapSolc(_solc);
        return _solc.version();
    } catch (error) {
        console.log(error);
    }

    return null;
})();

module.exports.compile = function() {
    if (compile == null) {
        throw new Error("missing solc; select a compiler version with `npm install solc`");
    }

    return compile.apply(this, Array.prototype.slice.call(arguments));
}

module.exports.getAddress = async function(signer, version) {

    // Get the Springboard address and code
    const springboardAddress = await signer.provider.resolveName((version || "v0") + ".rooted.eth");

    const code = await signer.provider.getCode(springboardAddress);

    const sender = await signer.getAddress();

    const codeBytes = ethers.utils.arrayify(code);
    const length = codeBytes.length;

    // This library requires the Springboard use metadata version 0, which
    // indicates the location within the Springboard's bytecode that the
    // Bootstrap code lives.
    if (codeBytes[length - 1] !== 0) {
        throw new Error("unsupported metadata version byte; update this library");
    }

    // Bootstrap bytecode size and offset (so we can compute the create2 initcode)
    const bsSize = (codeBytes[length - 3] << 8) | codeBytes[length - 2];
    const bsOffset = (codeBytes[length - 5] << 8) | codeBytes[length - 4];

    // Compute the address CREATE2 would generate for the signer
    return ethers.utils.getCreate2Address(
        springboardAddress,
        ethers.utils.zeroPad(sender, 32),
        ethers.utils.keccak256(codeBytes.slice(bsOffset, bsOffset + bsSize))
    )
}
