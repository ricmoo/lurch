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
    return StorageUint256(0xAc180e659dB90529b3A1890e9f113c6859Bf4B19).get(0);
}

function setPersistentValue(uint256 _value) public {
    StorageUint256(0xAc180e659dB90529b3A1890e9f113c6859Bf4B19).set(0, _value);
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
like codecopy and caller are hijacked so the executing initcode thinks it
is being deployed normally.

Caveats
-------

- This shold be thought of as fairly experimental at this point; please use it responsibly
- On average Lurch costs quite a bit more to run a contract through, in most cases about twice as much


License
-------

MIT License.
