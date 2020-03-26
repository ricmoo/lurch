pragma solidity ^0.6.1;

interface Storage {
    function get(uint256 key) view external returns (uint256);
    function set(uint256 key, uint256 value) external;
}

contract SimpleStorage {
    address payable public owner;
    uint256 public value;

    event Created(address indexed owner, uint256 value, uint256 endowment);
    event ValueChanged(address indexed author, uint256 oldValue, uint256 newValue);
    event PersistentValueChanged(address indexed author, uint256 oldValue, uint256 newValue);

    constructor(uint256 _value) public payable {
        owner = msg.sender;
        value = _value;
        emit Created(owner, value, msg.value);
    }

    function setValue(uint256 _value) public {
        emit ValueChanged(msg.sender, value, _value);
        value = _value;
    }

    // These proxy to external storage and will survive death
    function persistentValue() view public returns (uint256) {
        return Storage(0xAc180e659dB90529b3A1890e9f113c6859Bf4B19).get(0);
    }

    function setPersistentValue(uint256 _value) public {
        emit PersistentValueChanged(msg.sender, persistentValue(), _value);
        Storage(0xAc180e659dB90529b3A1890e9f113c6859Bf4B19).set(0, _value);
    }

    // We use this to destory this contract and prepare it for upgrading
    function die() public {
        require(msg.sender == owner);
        selfdestruct(owner);
    }
}
