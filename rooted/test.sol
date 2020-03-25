contract Test {
    uint256 public value;

    constructor() public {
        value = 42;
    }

    function setValue(uint256 _value) public {
        value = _value;
    }
}
