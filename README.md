![Lurch Logo](./assets/lurch-logo-wide.svg)

-----

Lurch VM
========

Lurch is an EVM implementation written in EVM, allowing ``eval``
functionality for smart contracts.

Uses
----

**Arbitrary Contract Size**

By using a Merkle Root, a contract can be broken into many smaller pieces.
when executing one, simply supply the Merkle-proof and runtime bytecode,
which can be verified before execution.

Optionally, contracts may have hidden (non-public) functions, which can be
part of the Merkle-tree, but kept secret until (or if) needed. This may
be useful for additional and complex recovery methods on contract wallets. 

**Hooking**

The EVM makes it simple to swap out, extend or intercept any EVM operation:

- Change storage slot based on caller or bytecode (hijack ``SSTORE`` and ``SLOAD``)
- Upgradable [Wisps](https://blog.ricmoo.com/wisps-the-magical-world-of-create2-5c2177027604) can have self-destruct-safe storage (forward ``SSTORE`` and ``SLOAD`` to external contract)
- Hijack precompiles (or add new precompiles) (hijack ``CALL`` and ilk)
- Allow arbitrary read-only code execution in your contraxct (revert on state changing opcodes)
- Alter the runtime environment, such as provide alternate sources of ``BALANCE``, ``CALLER``, ``ORIGIN``, etc.
    
**Counter-Facutal Verification**

No need to deploy a contract during a challenge, simply simulate the contract's
execution without needing to deploy it


Links
-------

- [Etherscan (mainnet)](https://etherscan.io/address/lurch.eth)
- [DevPost](https://devpost.com/software/lurch)
- Medium Article - coming soon

ABI
---

```
// Note: You will need to replace /any/ with your result
//       type, if you wish the JavaScript to automatically
//       parse the result.
function eval(bytes bytecode, bytes calldata) returns (any)
```

Example
-------

```javasccript
const { ether } = require("ethers");

// Connect to mainnet
const probider = ethers.utils.getDefautlProvider();

// Depending on your bytecode, change the return type
const iface = new ethers.Interface(["function eval(bytes, bytes) view returns (uint)"]);
const data = iface.encodeFunctionData("eval", [
  "0x602a60005260206000f3",   // Bytecode
  "0x"                        // Calldata
])

// Call lurch.eth with the encoded bytecode and calldata
provider.call({ to: "lurch.eth", data: data })
// 0x000000000000000000000000000000000000000000000000000000000000002a
```


License
-------

MIT License.
