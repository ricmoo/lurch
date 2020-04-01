Rooted: Far-Too-Easy-To-Upgrade Contracts
=========================================

The goal of Rooted is to simplify making upgradable Ethereum contracts.

With **Rooted**, any contract deployed by the same account will be
deployed to the same **Rooted Address**, everytime.

So, to upgrade a contract, have it self-destruct itself (in some safe,
gaurded manner) and then redeploy using the same account originally used.


How To Deploy
-------------

Since any given EOA will have exactly one **Rooted Address**, it is
recommended you create a new EOA for each contract you wish Rooted.
Otherwise, complication seeps back in, as you need contracts to dispatch
deployment calls.

1. Create a new EOA for your Contract
2. Fund that account 
3. Deploy your contract as usual, **except**: instead of an empty `to` address, use `v0-beta-0.rooted.eth`.

That's it! When you wish to upgrade your contract, simply use
whatever method exists on your contract to self-destruct it and
then follow the above steps again, with the new contract bytecode.


Command-Line Interface
----------------------

The command-line interface has the same options as the other
[ethers CLI utilities](https://docs-beta.ethers.io/cli/ethers/#sandbox-utility--help).
To install, use `npm install @ricmoo/rooted`, and can then be used with the
following usage:

```
Usage:
   rooted FILENAME [ OPTIONS ]

OPTIONS
  --contract                  specify the contract to deploy
  --args                      specify JSON encoded constructor args
  --no-optimize               do not run the optimizer
```

**Example:**

These operations were run on ropsten (the `--network ropsten` is
omitted for brevity), so each transaction hash can be looked up
on [Etherscan](https://ropsten.etherscan.io).

```
/home/ricmoo> npm install -g @ricmoo/rooted

/home/ricmoo> cat Test1.sol
contract Test1 {
    address public owner = msg.sender;
    string public value;

    constructor(string _value) public {
        value = _value;
    }

    function die() public {
        require(msg.sender == owner);
        selfdestruct(owner);
    }
}

/home/ricmoo> cat Test2.sol
contract Test2 {
    address payable public owner = msg.sender;

    function value() public view returns (string memory) {
        return "The cat came back...";
    }

    function die() public {
        require(msg.sender == owner);
        selfdestruct(owner);
    }
}

# Deploy
/home/ricmoo> rooted --account wallet.json Test1.sol --args '[ "Hello World" ]'
Deploy: contracts/tests/test1.sol
  Contract Address:  0x266bBB07e802890024eBd03512FbED1E3c961d83
Response:
  Hash:  0x35317670d0edf57c4eb8c75c0fa080c81f8ab30cde27e7d2db30b50b96be7293
  
/home/ricmoo> export ADDR="0x266bBB07e802890024eBd03512FbED1E3c961d83"

/home/ricmoo> ethers eval 'provider.getCode(process.env.ADDR)'
"0x608060405234801561001057600080fd5b50600436106100415760003560e01c806335f46994146100465780633fa4f245146100505780638da5cb5b146100cd575b600080fd5b61004e6100f1565b005b610058610116565b6040805160208082528351818301528351919283929083019185019080838360005b8381101561009257818101518382015260200161007a565b50505050905090810190601f1680156100bf5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6100d56101a3565b604080516001600160a01b039092168252519081900360200190f35b6000546001600160a01b0316331461010857600080fd5b6000546001600160a01b0316ff5b60018054604080516020600284861615610100026000190190941693909304601f8101849004840282018401909252818152929183018282801561019b5780601f106101705761010080835404028352916020019161019b565b820191906000526020600020905b81548152906001019060200180831161017e57829003601f168201915b505050505081565b6000546001600160a01b03168156fea2646970667358221220eb669057926d1e6d788f7eb4df1322e2d04c3e49790744f9c31fdca1a8e3074f64736f6c63430006040033"

/home/ricmoo> ethers eval '(new Contract(process.env.ADDR, [ "function value() view returns (string)" ], provider)).value()'
Hello World


# Destroy
/home/ricmoo> ethers --account wallet.json eval '(new Contract(process.env.ADDR, [ "function die()" ], accounts[0])).die()'
Response:
  Hash:  0xd74a31f8fb0ec36bcbae174a665e1f183d269bf122605a44355dfc6d0b7235ca

/home/ricmoo> ethers eval 'provider.getCode(process.env.ADDR)'
"0x"


# Redeploy (same address, new code)
/home/ricmoo> rooted --account wallet.json Test2.sol
Deploy: contracts/tests/test2.sol
  Contract Address:  0x266bBB07e802890024eBd03512FbED1E3c961d83
Response:
  Hash:  0x89cb3165cb8a27d08094b198dbe8279147c226de293b69b86ccca91fedf621f1

/home/ricmoo> ethers eval 'provider.getCode(process.env.ADDR)'
"0x608060405234801561001057600080fd5b50600436106100415760003560e01c806335f46994146100465780633fa4f245146100505780638da5cb5b146100cd575b600080fd5b61004e6100f1565b005b610058610116565b6040805160208082528351818301528351919283929083019185019080838360005b8381101561009257818101518382015260200161007a565b50505050905090810190601f1680156100bf5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6100d5610144565b604080516001600160a01b039092168252519081900360200190f35b6000546001600160a01b0316331461010857600080fd5b6000546001600160a01b0316ff5b6040805180820190915260148152732a34329031b0ba1031b0b6b2903130b1b597171760611b602082015290565b6000546001600160a01b03168156fea26469706673582212205320b56a7ffb50e87057e9097f43c461aeeda9bd441fa781680ac5a46535cea164736f6c63430006040033"

/home/ricmoo> ethers eval '(new Contract(process.env.ADDR, [ "function value() view returns (string)" ], provider)).value()'
The cat came back...
```


Persistent Storage
------------------

Since a self-destructed contract loses all its storage, there is
an external Storage contract available. To use it, simply specify
the interface you'd like (the selector is ignored) with keys which
must fit within a `bytes32` and values which must also fit within
a `bytes32`.

For example:

```
interface StorageUint256 {
    function get(uint256 key) view external returns (uint256);
    function set(uint256 key, uint256 value) external;
}        

interface StorageBytes32 {
    function get(bytes32 key) view external returns (bytes32);
    function set(bytes32 key, bytes32 value) external;
}        

interface StorageMishMash {
    function get(uint8 key) view external returns (bytes32);
    function set(uint8 key, bytes32 value) external;
}        
```

And in your contract, you can use:

```
function persistentValue() view public returns (uint256) {
    return StorageUint256(0x760158D4613e8851D0C5Ae906a81698da89f903a).get(0);
}

function setPersistentValue(uint256 _value) public {
    StorageUint256(0x760158D4613e8851D0C5Ae906a81698da89f903a).set(0, _value);
}                            
```

**Notes:**

- The slots are shared per-caller, so make sure the keys do no collide; for example, `bytes1(0x05)` and `uint8(5)` would both occupy the same storage.
- Accessing values in an external contract will incur addition gas costs; cache values and limit calls if possible


How does it work?
-----------------

It works by using a combination of two of our previous Hackathon projects,
[Wisps](https://blog.ricmoo.com/wisps-the-magical-world-of-create2-5c2177027604)
and [Lurch](https://github.com/ricmoo/lurch).

Wisps allow using `create2` to deploy contracts with different bytecode to
the same address, although it was intended to only live within a single
transaction, this allows contracts to live as long as is desired.

Lurch allows execution of EVM bytecode within an Ethereum contract, which
allows for hooks to alter the environment during runtime. In this case, opcodes
like `codecopy` and `caller` are hijacked so the executing initcode thinks it
is being deployed normally.


Caveats
-------

- This shold be thought of as fairly experimental at this point; please use it responsibly
- On average Lurch costs quite a bit more to run a contract through, around 300k gas more


License
-------

MIT License.
