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

