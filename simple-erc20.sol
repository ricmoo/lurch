pragma solidity ^0.6.3;

contract Token {
    string public symbol = "LRCH";
    string public name = "Lurch";
    uint8 public decimals = 0;

    mapping(address => uint256) private _balances;

    address public owner;

    event Test(uint);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() public {
        owner = msg.sender;
        _balances[msg.sender] = 10000;
        emit Test(36);
    }

    function test() public pure returns (uint) {
        return 42;
    }

    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }

    function transfer(address to, uint256 amount) public {
        require(_balances[msg.sender] >= amount);
        require(_balances[to] + amount > _balances[to]);
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }
}
