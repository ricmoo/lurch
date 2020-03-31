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
    address public owner = msg.sender;

    function value() public view returns (string) {
        return "The cat came back...";
    }

    function die() public {
        require(msg.sender == owner);
        selfdestruct(owner);
    }
}

# Deploy
/home/ricmoo> rooted --account wallet.json Test1.sol --args '[ "Hello World" ]'
/home/ricmoo> export ADDR=""
/home/ricmoo> ethers --account wallet.json eval 'provider.getCode(process.env.ADDR)'
"0x1234"
/home/ricmoo> ethers --account wallet.json eval '(new Contract(process.env.ADDR, [ "function value() view" ], accounts[0])).view()'
"Hello World"

# Destroy
/home/ricmoo> ethers --account wallet.json eval '(new Contract(process.env.ADDR, [ "function kill()" ], accounts[0])).kill()'
/home/ricmoo> ethers --account wallet.json eval 'provider.getCode(process.env.ADDR)'
"0x"

# Redeploy (same address, new code)
/home/ricmoo> rooted --account wallet.json Test2.sol --args '[ "The cat came back..." ]'
/home/ricmoo> ethers --account wallet.json eval 'provider.getCode(process.env.ADDR)'
"0x1234"
/home/ricmoo> ethers --account wallet.json eval '(new Contract(process.env.ADDR, [ "function value() view" ], accounts[0])).view()'
"The cat came back..."
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
