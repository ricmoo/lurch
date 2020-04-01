pragma solidity ^0.6.4;

contract Test1 {
    address payable public owner = msg.sender;
    string public value;

    constructor(string memory _value) public {
        value = _value;
    }

    function die() public {
        require(msg.sender == owner);
        selfdestruct(owner);
    }
}
