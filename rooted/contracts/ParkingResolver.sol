pragma solidity ^0.6.4;

/**
 *  ParkingResovler
 *
 *  A simple Resolver to point any number of ENS names to
 *  fixed values.
 *
 */


interface ReverseRegistrar {
    function claim(address owner) external returns (bytes32 node);
}

interface AbstractENS {
    function owner(bytes32 node) external view returns (address);
}


contract ParkingResolver {
    bytes4 constant INTERFACE_META_ID         = 0x01ffc9a7;
    bytes4 constant ADDR_INTERFACE_ID         = 0x3b3b57de;
    bytes4 constant TEXT_INTERFACE_ID         = 0x59d1d43c;
    bytes4 constant CONTENTHASH_INTERFACE_ID  = 0xbc1c58d1;

    // namehash('addr.reverse')
    bytes32 constant NODE_RR = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    address payable public owner;

    AbstractENS private _ens;

    // Resolver properties
    address private _addr;
    mapping (string => string) private _text;
    bytes private _contenthash;


    constructor() public {
        owner = msg.sender;
        _addr = owner;
        _ens = AbstractENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
        ReverseRegistrar(_ens.owner(NODE_RR)).claim(owner);
    }

    function die() external {
        require(msg.sender == owner);
        selfdestruct(owner);
    }


    function addr(bytes32 nodehash) external view returns (address) {
        return _addr;
    }

    function setAddr(bytes32 nodehash, address addr) external {
        require(msg.sender == owner);
        _addr = addr;
    }


    function text(bytes32 nodehash, string calldata key) external view returns (string memory) {
        return _text[key];
    }

    function setText(bytes32 nodehash, string calldata key, string calldata value) external {
        require(msg.sender == owner);
        _text[key] = value;
    }


    function contenthash(bytes32 node) external view returns (bytes memory) {
        return _contenthash;
    }

    function setContenthash(bytes32 nodehash, bytes calldata contenthash) external {
        require(msg.sender == owner);
        _contenthash = contenthash;
    }


    // EIP-165
    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return (interfaceID == ADDR_INTERFACE_ID ||
                interfaceID == TEXT_INTERFACE_ID ||
                interfaceID == CONTENTHASH_INTERFACE_ID ||
                interfaceID == INTERFACE_META_ID);
    }
}
