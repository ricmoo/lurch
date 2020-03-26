; Generic Data Storage Contract
;
; This can be used by Wisp Contracts as a storage space that
; will persist across self-destructs. Any caller of this
; contract get their own slots in this contract.
;
;
; API
;
; interface Storage {
;     function getXXX(bytes32 key) view returns (bytes32);
;     function setXXX(bytes32 key, bytes32 value);
; }
;
; The function selector (e.g. getXXX and setXXX) is ignored. The
; only important thing is that all types are fixed-width up to
; 32 bytes. For example: uint256, address, int8, bool.
;
; Also note that callers should ensure keys are unique. If two
; forms are used which can collide (e.g. uint256 and bytes32),
; the caller is responsible to make sure keys are unique.

;;;;;;;;

; Copy the Storage contract to memory
codecopy(0, $Storage, #Storage)

; Return the contract for the init code
return (0, #Storage);

; The on-chain contract
@Storage {

    ; non-payable (throw if we receive value)
    jumpi($error, callvalue)

    ; If calldata is setXXX(bytes32 key, bytes32 value), use set
    jumpi($set, eq(calldatasize, 68))

    ; We calldata is getXXX(bytes32 key), use get
    jumpi($get, eq(calldatasize, 36))

    @error:
        ; No matching selector (length) of data length is bad
        revert(0, 0)

    @get:
        ; Compute the caller's storage slot (i.e. keccak(caller + key))
        mstore(0, caller)
        mstore(0x20, calldataload(4))

        mstore(0, sload(sha3(0, 64)));
        return(0, 32)

    @set:
        ; Compute the caller's storage slot (i.e. keccak(caller + key))
        mstore(0, caller)
        mstore(0x20, calldataload(4))

        sstore(sha3(0, 64), calldataload(36))
        return (0, 0)
}
