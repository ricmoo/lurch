; Springboard (rooted)
;
; The Springboard is used to deploy contracts at a stable
; address, based on the caller. Any two contracts deployed
; by sending the initcode to rooted.eth, from the same
; address (EOA or contract) will be deployed to the same
; address.
;

;
; Storage Layout
; [1]      = pending bytecode caller (or 0 if no pending bytecode)
; [2]      = pending bytecode length
; [32 * i] = pending bytecodecode[i:i + 32]
;

;
; Deploy the Springboard
;

{{!
    const provider = ethers.getDefaultProvider(defines.Network);
    const ens = new ethers.Contract(provider.network.ensAddress, [
        "function owner(bytes32) view returns (address)"
    ], provider);
}}

; Claim our record in the ENS reverse registrar by giving
; it's record to the deployer who will be able to set the
; reverse record
mstore(0, {{= sighash("claim(address owner)") }})
mstore(32, caller)
call(gas, {{= ens.owner(ethers.utils.namehash("addr.reverse")) }}, 0, 28, 36, 0, 0)

; Return the Springboard source
codecopy(0, $Springboard, #Springboard);
return (0, #Springboard);

@Springboard {

    ; We store the (length + 1) so that we can detect whether we are
    ; being called externally or from the bootstrap, even if the
    ; initcode length is 0

    ; Load the caller
    sload(1)
    dup1()

    ; [ (external ? 0: caller), (external ? 0: caller) ]

    ; Are we being called from the bootstrap?
    jumpi($fromBootstrap, $$)

    ; ... falls-through ...

    ; Called when an external call is made to the Springboard
    @fromExternal:
        ; [ 0 ]

        ; Storage[0] = caller
        sstore(1, caller)

        ; Storage[2] = length
        sstore(2, calldatasize)

        ; Copy the calldata (which is the initcode passed in) to Storage

        ; [ i = 0 ]  (reuse duplicate empty length)

        @copyCalldataToStorage:
            ; [ i ]

            ; Storage[i] = calldata[i: i + 32]
            calldataload(dup1)         ; [ i, calldata[i: i + 32] ]
            dup2()                     ; [ i, calldata[i: i + 32], i ]
            sstore($$, $$)             ; [ i ]

            ; i += 32
            add(0x20, $$)              ; [ i + 32 ]

            ; if i < calldata.length: continue
            calldatasize()             ; [ i + 32, calldata.length ]
            dup2()                     ; [ i + 32, calldata.length, i + 32 ]
            jumpi($copyCalldataToStorage, lt($$, $$))

        ; [ junk ]

        ; Copy the bootstrap into memory
        codecopy(0, $Bootstrap, #Bootstrap)

        ; Use CREATE2 to execute the bootstrap as its initcode (passing all ether along)
        create2(callvalue, 0, #Bootstrap, caller)

        ; [ junk, create2.address ]

        ; Revert if the create2 failed
        jumpi($skipCreateFailed, dup1)
        revert(0, 0)
        @skipCreateFailed:

        ; Return the address of the new contract (ABI encoded)
        mstore(0, $$)

        log2(0, 32, {{= topichash("Deployed(address indexed deployer, address created)") }}, caller)

        return(0, 32)

    ; Called from the Bootstrap
    @fromBootstrap:
        ; [ caller ]

        ; Prepare the calldata for Lurch (less callbalue) and clear Storage
        ; [ caller: 32 bytes ] [ bytecode.length: 32 bytes ] [ bytecode: XX bytes ]

        ; Lurch parameter: caller
        mstore(0, $$)
        sstore(1, 0)            ; (the pending bytecode caller)

        ; Load the length
        sload(2)

        ; Lurch parameter: bytecode.length
        mstore(32, dup1)
        sstore(2, 0)           ; (the pending bytecode length)

        ; [ length ]

        ; Copy (and clear) the initcode from Storage to memory
        0x00

        ; [ length, i = 0 ]

        @moveStorageToMemory:
            ; [ length, i ]

            ; Load from Storage[i]
            sload(dup1())                 ; [ length, i, initcode[i: i + 32] ]
            dup2()                        ; [ length, i, initcode[i: i + 32], i ]

            ; Copy initcode to memory
            mstore(add(64, $$), $$)                ; [ length, i ]

            ; Clear Storage[i]
            0x00                          ; [ length, i, 0 ]
            dup2()                        ; [ length, i, 0, i ]
            sstore($$, $$)                ; [ length, i ]

            ; i += 32
            add(0x20, $$)                 ; [ length, i + 32 ]

            ; if i < initcode.length: continue
            dup2()                        ; [ length, i + 32, length ]
            dup2()                        ; [ length, i + 32, length, i + 32 ]
            jumpi($moveStorageToMemory, lt($$, $$))

        ; [ length, junk ]

        pop()

        ; Return the result of executing the initcode to the bootstrap
        return(0, add(64, $$))

    ; The Bootstrap is a static chunk of bytecode that will be
    ; used to callback into the Springboard to perform the
    ; initcode. Because it is static, all CREATE2 addresses will
    ; be dependent exclusively on the salt, which is the caller.
    @Bootstrap {

        ; CALL into the Springboard (the storage has bee set), which will:
        ; - reset all the initcode in Storage to 0
        ; - return the initcode to execute
        call(gas, caller, 0, 0, 0, 0, 0)

        ; Reert if the call failed
        jumpi($skipFetchFailed, $$)
        revert(0, 0)
        @skipFetchFailed:

        ; Set up the Lurch (Rooted) layout
        ; [ caller: 32 bytes ] [ bytecode.length: 32 bytes ] [ bytecode: XX bytes ]
        returndatacopy(0, 0, returndatasize)

        ; DELEGATECALL Lurch, with the initcode, which will execute it,
        ; returning the result of the initcode
        delegatecall(gas, {{= defines.LurchAddress }}, 0, returndatasize, 0, 0)

        ; Revert if the call into Lurch failed
        jumpi($skipLurchFailed, $$)
        revert(0, 0)
        @skipLurchFailed:

        ; Now return the result of executing the initcode
        returndatacopy(0, 0, returndatasize)
        return(0, returndatasize)
    }

    ; Include some useful version info so we can compute addresses offline
    ; - The last byte indicates the version of the metadata (i.e. 0)
    ; - The prior 2 bytes indicate length of the Bootstrap
    ; - The prior 2 bytes indicate the offset of the Bootstrap
    @Version[
        {{= concat([ Opcode.from("PUSH5"), zeroPad(Bootstrap.offset, 2), zeroPad(Bootstrap.length, 2), 0 ]) }}
    ]
}
