; Lurch VM
;

; Result
; 0 - error
; 1 - return
; 2 - stop
; 3 - write in static context
; 4 - invalid

; Memory Layout
; Slot    
;  0     PC
;  1     Bytecode Offset (into calldata)
;  2     Bytecode Length
;  3     Calldata Offset (into calldata)
;  4     Calldata Length
;  5     Virtualized Memory Offset
;
;
;

{{!

    function slot(index) {
        if (index == null) { throw new Error("invalid slot"); }
        return 32 * index;
    }

    const PC        = 0;
    const BC_OFF    = 1;
    const BC_LEN    = 2;
    const CD_OFF    = 3;
    const CD_LEN    = 4;
    const MEM       = 5;
    const MEM_BASE  = 6;
}}


; Deployment initcode (we copy everything including this bootstrap
; so the offsets are easier to work with for replacing placeholders)
codecopy(0, $_, #_)

; Inject my real address into the contract (overwrite the PUSH32)
mstore({{= myAddress.offset + 1 }}, address)

; Return the Lurch Contract
return($lurch, #lurch)


@lurch {
    ; Jump to the start (since we only start once, we can use a higher
    ; jumpdest offset, reserving these low ones for frequently used things)
    jump($start)

    ; Execute a push operation
    ; - Caller must push the count pushXX of bytes to push
    ; - Return places the value on the stack
    @pushOp:
        ; [ pushXX ]

        dup1()
        sub(256, shl(3, $$))

        ; [ pushXX, 256 - pushXX * 8 ]

        calldataload(add(0x01, add(mload({{= slot(PC) }}), mload({{= slot(BC_OFF) }}))))
        swap1()

        ; [ pushXX, push_literal[0..32], pushXX ]

        ; Trim off any extra bytes on the right
        shr($$, $$)
        swap1()

        ; [ push_literal[0..32], pushXX ]

        ; Update the PC to skip past this entire PUSH operation
        mstore({{= slot(PC) }}, add(0x01, add(mload({{= slot(PC) }}), $$)))

        ; [ push_literal[0..32] ]

        jump($next)

    ; Places a 1 on the stack if this MUST be static, 0 otherwise
    ; Caller must place the return jumpdest on the stack before
    @isStatic:
        ; [ return_jumpdest ]

        ; Put my real address here at deployment(to detect if in a call delegate)
        @myAddress[ ]
        {{= zeroPad(0, 32) }}

        eq(address, $$)

        ; Return from this sub-routine
        swap1()
        jump($$)
        
    @popIncrement:
        ; Clean up the stack from a JUMPI
        pop()

        ; falls-through

    @increment:
        ; Increment the PC by 1
        mstore({{= slot(PC) }}, add(mload({{= slot(PC) }}), 1))

        ; falls-through

    @next:
        ; Get the current PC
        mload({{= slot(PC) }})

        ; [ PC ]

        ; Bounds checking; compute a multiplier (0 if out-of-bounds, 1 otherwise)
        lt(dup2(), mload({{= slot(BC_LEN) }}))
        swap1()

        ; [ ((PC < BC_LEN) ? 1: 0), PC ]

        ; Get the current operation
        shr(248, calldataload(add(mload({{= slot(BC_OFF) }}), $$)))

        ; Use the bounds checking multiplier from above
        mul($$, $$)

        ; [ ((PC < BC_LEN) ? opcode: STOP) ]

        ; Jump into the operation jump table
        jump(add($operations, mul(6, $$)))

    @invalidOp:
        ; @TODO: when redoing the jump table, this can be embedded?
        invalid();

    ;;;;
    ;;;; Anything after this can have 2-byte offsets
    ;;;;

    @sha3Op:
        ; [ ... memDestOffset ]
        add(mload({{= slot(MEM) }}), $$)
        sha3($$, $$)
        jump($increment)        

    @calldataloadOp:
        ; [ ... offset ]
        add(mload({{= slot(CD_OFF) }}), $$)
        calldataload($$)
        jump($increment)

    @calldatasizeOp:
        ; [ ... ]
        mload({{= slot(CD_LEN) }})
        jump($increment)

    @calldatacopyOp:
        ; [ ... length, offset, dstMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        swap1()
        add(mload({{= slot(CD_OFF) }}), $$)
        swap1()
        calldatacopy($$, $$, $$)
        jump($increment)

    @codesizeOp:
        ; [ ... ]
        mload({{= slot(BC_LEN) }})
        jump($increment)

    @codecopyOp:
        ; [ ... length, offset, dstMemOffset]
        add(mload({{= slot(MEM) }}), $$)
        swap1()
        add(mload({{= slot(BC_OFF) }}), $$)
        swap1()
        calldatacopy($$, $$, $$)
        jump($increment)

    @extcodecopyOp:
        ; [ ... length, offset, dstMemOffset, address]
        swap1()
        add(mload({{= slot(MEM) }}), $$)
        swap1()
        extcodecopy($$, $$, $$, $$)
        jump($increment)

    
    ; needs call to test...
    @returndatacopyOp:
        ; [ ... length, offset, dstMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        returndatacopy($$, $$, $$)
        jump($increment)

    @mloadOp:
        ; [ ... dstMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        mload($$)
        jump($increment)        

    @mstoreOp:
        ; [ ... value, dstMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        mstore($$, $$)
        jump($increment)        

    @mstore8Op:
        ; [ ... value, dstMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        mstore8($$, $$)
        jump($increment)        

    @jumpOp:
        ; [ ... target ]

        dup1()

        ; [ ... target, target ]

        ; Store the updated PC (we will die below if it is not a JUMPDEST)
        mstore({{= slot(PC) }}, add(1, $$))

        ; Get the opcode at target
        shr(248, calldataload(add(mload({{= slot(BC_OFF) }}), $$)))

        ; [ ... opcode ]

        ; If it is a JUMPDEST, continue (skipping increment). Otherwise, die
        jumpi($next, eq({{= Opcode.from("JUMPDEST").value }}, $$))
        jump($invalidOp)

    @jumpiOp:
        ; [ ... notZero, target ]
        swap1()
        jumpi($popIncrement, isZero($$))
        jump($jumpOp)

    @pcOp:
        ; [ ]
        mload({{= slot(PC) }})
        jump($increment)

    @msizeOp:
        ; [ ]
        sub(msize, {{= slot(MEM_BASE) }})
        jump($increment)

    @log0Op:
        ; [ ... length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        log0($$, $$)
        jump($increment)        

    @log1Op:
        ; [ ... topic0, length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        log1($$, $$, $$)
        jump($increment)        

    @log2Op:
        ; [ ... topic1, topic0, length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        log2($$, $$, $$, $$)
        jump($increment)        

    @log3Op:
        ; [ ... topic2, topic1, topic0, length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        log3($$, $$, $$, $$, $$)
        jump($increment)        

    @log4Op:
        ; [ ... topic3, topic2, topic1, topic0, length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        log4($$, $$, $$, $$, $$, $$)
        jump($increment)

    @createOp:
        ; [ ... srcLength, srcOffset, value ]

        swap1()
        add(mload({{= slot(MEM) }}), $$)
        swap1()

        create($$, $$, $$)

        jump($increment)

    @callOp:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add(mload({{= slot(MEM) }}), $$)
        swap3()

        swap5()
        add(mload({{= slot(MEM) }}), $$)
        swap5()

        call($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    @callcodeOp:
        ; @TODO: Is this correct? No good docs on CALLCODE...
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add(mload({{= slot(MEM) }}), $$)
        swap3()

        swap5()
        add(mload({{= slot(MEM) }}), $$)
        swap5()

        callcode($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    @returnOp:
        ; [ ... length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        return($$, $$)

        ;; TEMP -debug remove the range
        ;pop()
        ;pop()

        ;;; DEBUG
        ;dup1()
        ;mstore({{= slot(PC) }}, $$)
        ;return(0, {{= 32 * 8 }})
        ;;; /DEBUG

    @delegatecallOp:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add(mload({{= slot(MEM) }}), $$)
        swap2()

        swap4()
        add(mload({{= slot(MEM) }}), $$)
        swap4()

        delegatecall($$, $$, $$, $$, $$, $$)

        jump($increment)

    @create2Op:
        ; [ ... salt, srcLength, srcOffset, value ]

        swap1()
        add(mload({{= slot(MEM) }}), $$)
        swap1()

        create2($$, $$, $$, $$)

        jump($increment)

    @staticcallOp:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add(mload({{= slot(MEM) }}), $$)
        swap2()

        swap4()
        add(mload({{= slot(MEM) }}), $$)
        swap4()

        staticcall($$, $$, $$, $$, $$, $$)

        jump($increment)
    
    @revertOp:
        ; [ ... length, srcMemOffset ]
        add(mload({{= slot(MEM) }}), $$)
        revert($$, $$)

    @start:
        ; @TODO: Use various decoing depending on the selector
        ; - eval(bytes bytecode)
        ; - eval(bytes bytecode, bytes calldata)
        ; - evalStrict(bytes bytecode)
        ; - evalStrict(bytes bytecode, bytes calldata)
        ; - jumpdest(bytes bytecode)

        ; Stretch goals
        ; - evalStrict(bytes bytecode, bytes calldata, bytes hooks)
        ; - eval(bytes bytecode, bytes calldata, bytes hooks)

        ; Memory
        ; Slot   Value
        ;  0      0 (PC)

        ; Load the bytecode size and offset
        0x04                                             ; [ 0x04 ]
        dup1()                                           ; [ 0x04, 0x04 ]
        dup1()                                           ; [ 0x04, 0x04, 0x04 ]
        calldataload($$)                                 ; [ 0x04, 0x04, bytecode_offset ]
        add($$, $$)                                      ; [ 0x04, bytecode_length ]
        dup1()                                           ; [ 0x04, bytecode_length, bytecode_length ]
        mstore({{= slot(BC_LEN) }}, calldataload($$))    ; [ 0x04, bytecode_length ]
        add(32, $$)                                      ; [ 0x04, bytecode_data ]
        mstore({{= slot(BC_OFF) }}, $$)                  ; [ 0x04 ]

        ; Memory
        ; Slot   Value
        ;  1      bytecode_offset
        ;  2      bytecode_length

        ; Load the calldata size and offset
        0x24                                             ; [ 0x04, 0x24 ]
        calldataload($$)                                 ; [ 0x04, calldata_offset ]
        add($$, $$)                                      ; [ calldata_length ]
        dup1()                                           ; [ calldata_length, calldata_length ]
        mstore({{= slot(CD_LEN) }}, calldataload($$))    ; [ calldata_length ]
        add(32, $$)                                      ; [ calldata_data ]
        mstore({{= slot(CD_OFF) }}, $$)                  ; [ ]

        ;  3      calldata_offset
        ;  4      calldata_length

        mstore({{= slot(MEM); }}, {{= slot(MEM_BASE) }})

        ;  5      memory_base => 6

        ; Start exeuting the VM
        jump($next)


    ; Create an addressable jump destination block

    ; This table keeps all instructions at 6 bytes each, so a given
    ; operation can be found at ($operations + 6 * opcode). Any complex
    ; opcodes need to jump to an additional location for extra logic.

    ; The stack must be intact (from the virtualized environment's point
    ; of view) when entering this jump table.
    
    {{!

        // Notes:
        // - We pad with STOP (i.e. 0) because 0 is cheaper to deploy

        // Simple Special cases
        const special = {
            SHA3: sha3Op,

            MLOAD: mloadOp,
            MSTORE: mstoreOp,
            MSTORE8: mstore8Op,

            LOG0: log0Op,
            LOG1: log1Op,
            LOG2: log2Op,
            LOG3: log3Op,
            LOG4: log4Op,

            CALLDATALOAD: calldataloadOp,
            CALLDATASIZE: calldatasizeOp,
            CALLDATACOPY: calldatacopyOp,
            CODESIZE: codesizeOp,
            CODECOPY: codecopyOp,
            EXTCODECOPY: extcodecopyOp,
            RETURNDATACOPY: returndatacopyOp,

            JUMP: jumpOp,
            JUMPI: jumpiOp,

            PC: pcOp,
            MSIZE: msizeOp,

            CREATE: createOp,
            CALL: callOp,
            CALLCODE: callcodeOp,
            RETURN: returnOp,
            DELEGATECALL: delegatecallOp,
            CREATE2: create2Op,
            STATICCALL: staticcallOp,
            REVERT: revertOp,
        };

        // Some sanity checking on our jump table
        for (const mnemonic in special) {
            if (!special[mnemonic]) { throw new Error(`missing jumpdest: ${ mnemonic }`); }
            if (Opcode.from(mnemonic) == null) {
                throw new Error(`unknown opcode: ${ mnemonic }`);
            }
        }
        
        const code = [ ];
        let lastLength = 2;
        for (let i = 0; i < 256; i++) {
            let opcode = Opcode.from(i);

            if (opcode == null) {
                // Trap Invalid opcodes for possible reporting
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                //code.push(Opcode.from("PUSH2"));                  // 1 byte
                //code.push(zeroPad(hexlify(invalidOp), 2));        // 2 bytes
                //code.push(Opcode.from("JUMP"));                   // 1 byte                
                code.push(Opcode.from("STOP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
            
            } else if (opcode.mnemonic === "JUMPDEST") {
                // Jump dests can be optimized
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(increment), 1));        // 1 byte
                code.push(Opcode.from("JUMP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte

            } else if (opcode.isPush()) {
                // PUSH opcodes include their push count on the stack
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(opcode.isPush()), 1));  // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(pushOp), 1));           // 1 byte
                code.push(Opcode.from("JUMP"));                   // 1 byte                

            } else if (special[opcode.mnemonic]) {
                // Return is hijacked for now for testing...
                code.push(Opcode.from("JUMPDEST"));                        // 1 byte
                code.push(Opcode.from("PUSH2"));                           // 1 byte
                code.push(zeroPad(hexlify(special[opcode.mnemonic]), 2));  // 2 bytes
                code.push(Opcode.from("JUMP"));                            // 1 byte
                code.push(Opcode.from("STOP"));                            // 1 byte
                
            } else {
                // Most things just work with the stack
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(opcode);                                // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(increment), 1));        // 1 bytes
                code.push(Opcode.from("JUMP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
            }

            // Make sure the opcode sequence is exactly 6 bytes
            if (concat(code).length !== lastLength + 12) {
                console.log(concat(code).length, lastLength, code);
                throw new Error("wrong bytecode length for jump table: " + i);
            }
            lastLength = concat(code).length;
        }
    }}

    @operations[ {{= concat(code) }} ]
}
