Swapable (TBR)
==============

Send a normal deployment transaction to this address and it will
be deployed at an address based only on the sender.

If the contract self-destructs and the same account deploys a
new contract, it will be placed at the same address, allowing
a contract to be upgraded easily.

To maintain any data across deployments, the contract may also use
the extenral storage contract.
