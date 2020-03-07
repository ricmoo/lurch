; Lurch VM
;

; todo: store PC wrt BC

; Result
; 0 - error
; 1 - return
; 2 - stop
; 3 - write in static context
; 4 - invalid

; Memory Layout
; Slot   Purpose
;  0      PC
;  1      Bytecode Offset (into calldata)
;  2      Bytecode Length
;  3      (calldata offset << 80) | (scratch << 64) | (calldata_length)
;  4      Virtualized Memory Offset
;  5      ... Virtualized Memory starts here ...
;
;
;

{{!
    const SLOT_PC        = 0x00;
    const SLOT_BC_OFF    = 0x20;
    const SLOT_BC_LEN    = 0x40;

    const SLOT_CD        = 0x60;
    const CD_OFF_SHIFT   = 80;
    const CD_LEN_MASK    = 0xffff;

    // The offset (in bytes) into SLOT_CD where the left
    // edge of the SCRATCH begins.
    const SLOT_SCRATCH   = SLOT_CD + 0x20 - 2 - 2;

    const SLOT_MEM       = 0x80;
    const SLOT_MEM_BASE  = 0xa0;
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
        ; [ ... target ]

        ; Clean up the stack from a JUMPI
        pop()

        ; falls-through

    @increment:
        ; Increment the PC by 1
        mstore({{= SLOT_PC }}, add(mload({{= SLOT_PC }}), 1))

        ; falls-through

    @next:
        ; The length below for the codecopy to fetch the jumpdest
        0x02

        ; Get the current PC
        mload({{= SLOT_PC }})

        ; [ 0x02, PC ]

        ; Bounds checking; compute a multiplier (0 if out-of-bounds, 1 otherwise)
        lt(dup2(), mload({{= SLOT_BC_LEN }}))
        swap1()

        ; [ 0x02, ((PC < BC_LEN) ? 1: 0), PC ]

        ; Get the current operation
        shr(248, calldataload(add(mload({{= SLOT_BC_OFF }}), $$)))

        ; Use the bounds checking multiplier from above
        mul($$, $$)

        ; [ 0x02, ((PC < BC_LEN) ? opcode: STOP) ]

        ; Copy the jumpdest location in code from the jump table
        add($operations, shl(1, $$))

        ; [ 0x02, (((jump_table[opcode]) << 240) | junk) ]

        ; Load the jumpdest into scratch and trim off all the junk
        codecopy({{= SLOT_SCRATCH }}, $$, $$)
        shr(240, mload({{= SLOT_SCRATCH }}))

        ; Jump into the operation jump table
        jump($$)


    {{!
        const jumpTable = [ ];
        const added = { };
        for (let i = 0; i < 256; i++) {
            jumpTable[i] = opInvalid;
        }

        function setJumpTable(offset, opcode) {
            //console.log(`Adding ${ Opcode.from(opcode).mnemonic } to ${ offset }.`);
            const index = offset * 2;
            if (added[opcode]) { throw new Error("Jump Table already has that value: " + opcode); }
            added[opcode] = true;
            jumpTable[opcode] = offset;
        }

        function length(ops) {
            return arrayify(ops).length;
        }


        function getSimpleOp(offset, opcode) {
            setJumpTable(offset, opcode);
            const ops = [ ];
            ops.push(Opcode.from("JUMPDEST"))
            ops.push(opcode)
            ops.push(Opcode.from("PUSH1"))
            ops.push(increment)
            ops.push(Opcode.from("JUMP"))
            return concat(ops);
        }

        // [ ... ]
        function getSimpleOpRange(offset, start, end) {
            const ops = [ ]
            for (let i = start; i <= end; i++) {
                ops.push(getSimpleOp(offset + length(concat(ops)), i));
            }
            return concat(ops);
        }

        // [ ... topicN, ... , topic0, length, srcMemOffset ]
        function getLogOp(offset, opcode) {
            setJumpTable(offset, opcode);

            const ops = [ ];
            ops.push(Opcode.from("JUMPDEST"))

            // add(mload SLOT_MEM), $$)
            ops.push(Opcode.from("PUSH1"))
            ops.push(SLOT_MEM);
            ops.push(Opcode.from("MLOAD"));
            ops.push(Opcode.from("ADD"));

            // logN( ... )
            ops.push(opcode)

            // jump(increment)
            ops.push(Opcode.from("PUSH1"))
            ops.push(increment)
            ops.push(Opcode.from("JUMP"))

            return concat(ops);
        }

        function getPushOps(offset) {
            const ops = [ ];
            for (let i = 1; i <= 32; i++) {
                setJumpTable(offset + ops.length, 0x60 + i - 1);
                ops.push(Opcode.from("JUMPDEST"))

                // Load the PC
                ops.push(Opcode.from("PUSH1"));
                ops.push(SLOT_PC);
                ops.push(Opcode.from("MLOAD"));

                // [ PC ]

                // Add the entire push operation to the PC (1 + i)
                ops.push(Opcode.from("DUP1"));             // [ PC, PC ]
                ops.push(Opcode.from("PUSH1"));
                ops.push(i + 1);                           // [ PC, PC, (i + 1) ]
                ops.push(Opcode.from("ADD"));              // [ PC, (PC + i + 1) ]
                ops.push(Opcode.from("PUSH1"));
                ops.push(SLOT_PC);                         // [ PC, (PC + i + 1), SLOT_PC ]
                ops.push(Opcode.from("MSTORE"));           // [ PC ]

                // [ PC ]

                // Load the value from calldata (aligned to the left)
                ops.push(Opcode.from("PUSH1"));
                ops.push(1);                                // [ PC, 1 ]
                ops.push(Opcode.from("ADD"));               // [ PC + 1 ]
                ops.push(Opcode.from("PUSH1"));
                ops.push(SLOT_BC_OFF);
                ops.push(Opcode.from("MLOAD"));             // [ PC + 1, BC.offset ]
                ops.push(Opcode.from("ADD"));               // [ PC + 1 + BC.offset ]
                ops.push(Opcode.from("CALLDATALOAD"));      // [ (value[0:i] + junk[i:32]) ]

                // Shift off the bottom junk (this is a nop for PUSH32)
                if (i !== 32) {
                    ops.push(Opcode.from("PUSH1"));
                    ops.push(256 - 8 * i);
                    ops.push(Opcode.from("SHR"));
                }

                // Jump back in
                ops.push(Opcode.from("PUSH1"))
                ops.push(next);
                ops.push(Opcode.from("JUMP"))
            }
            return concat(ops);
        }
    }}

    {{! setJumpTable(opStop, Opcode.from("STOP").value) }}
    @opStop:
        stop


    ;;;;;;;;;;;;;;;
    ;; Math Operations (0x01 - 0x0b)

    @opsMaths[ {{= getSimpleOpRange(opsMaths.offset, 0x01, 0x0b) }} ]


    ;;;;;;;;;;;;;;;
    ;; Compare and Bitwise Operations (0x10 - 0x1d)

    @opsCompareBitwise[ {{= getSimpleOpRange(opsCompareBitwise.offset, 0x10, 0x1d) }} ]


    ;;;;;;;;;;;;;;;
    ;; Identity Operations (0x20)

    {{! setJumpTable(opSha3, Opcode.from("SHA3").value) }}
    @opSha3:
        ; [ ... memDestOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        sha3($$, $$)
        jump($increment)


    ;;;;;;;;;;;;;;;
    ;; Environment Information (0x30 - 0x3f)

    @opAddress[ {{= getSimpleOp(opAddress.offset, Opcode.from("ADDRESS").value) }} ]
    @opBalance[ {{= getSimpleOp(opBalance.offset, Opcode.from("BALANCE").value) }} ]
    @opOrigin[ {{= getSimpleOp(opOrigin.offset, Opcode.from("ORIGIN").value) }} ]
    @opCaller[ {{= getSimpleOp(opCaller.offset, Opcode.from("CALLER").value) }} ]
    @opCallvalue[ {{= getSimpleOp(opCallvalue.offset, Opcode.from("CALLVALUE").value) }} ]

    {{! setJumpTable(opCalldataload, Opcode.from("CALLDATALOAD").value) }}
    @opCalldataload:
        ; [ ... offset ]
        add(shr({{= CD_OFF_SHIFT }}, mload({{= SLOT_CD }})), $$)
        calldataload($$)
        jump($increment)

    {{! setJumpTable(opCalldatasize, Opcode.from("CALLDATASIZE").value) }}
    @opCalldatasize:
        ; [ ... ]
        mload(and({{= CD_LEN_MASK }}, {{= SLOT_CD }}))
        jump($increment)

    {{! setJumpTable(opCalldatacopy, Opcode.from("CALLDATACOPY").value) }}
    @opCalldatacopy:
        ; [ ... length, offset, dstMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        swap1()
        add(mload(shr({{= CD_OFF_SHIFT}}, {{= SLOT_CD }})), $$)
        swap1()
        calldatacopy($$, $$, $$)
        jump($increment)

    {{! setJumpTable(opCodesize, Opcode.from("CODESIZE").value) }}
    @opCodesize:
        ; [ ... ]
        mload({{= SLOT_BC_LEN }})
        jump($increment)

    {{! setJumpTable(opCodecopy, Opcode.from("CODECOPY").value) }}
    @opCodecopy:
        ; [ ... length, offset, dstMemOffset]
        add(mload({{= SLOT_MEM }}), $$)
        swap1()
        add(mload({{= SLOT_BC_OFF }}), $$)
        swap1()
        calldatacopy($$, $$, $$)
        jump($increment)

    @opGasprice[ {{= getSimpleOp(opGasprice.offset, Opcode.from("GASPRICE").value) }} ]
    @opExtcodesize[ {{= getSimpleOp(opExtcodesize.offset, Opcode.from("EXTCODESIZE").value) }} ]

    {{! setJumpTable(opExtcodecopy, Opcode.from("EXTCODECOPY").value) }}
    @opExtcodecopy:
        ; [ ... length, offset, dstMemOffset, address]
        swap1()
        add(mload({{= SLOT_MEM }}), $$)
        swap1()
        extcodecopy($$, $$, $$, $$)
        jump($increment)

    @opReturndatasize[ {{= getSimpleOp(opReturndatasize.offset, Opcode.from("RETURNDATASIZE").value) }} ]

    ; needs call to test...
    {{! setJumpTable(opReturndatacopy, Opcode.from("RETURNDATACOPY").value) }}
    @opReturndatacopy:
        ; [ ... length, offset, dstMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        returndatacopy($$, $$, $$)
        jump($increment)

    @opExtcodehash[ {{= getSimpleOp(opExtcodehash.offset, Opcode.from("EXTCODEHASH").value) }} ]


    ;;;;;;;;;;;;;;;
    ;; Block Information (0x40 - 0x45)

    @opsBlock[ {{= getSimpleOpRange(opsBlock.offset, 0x40, 0x45) }} ]


    ;;;;;;;;;;;;;;;
    ;; Stack, Memory, Storage and Flow Operations (0x50 - 0x5b)

    @opPop[ {{= getSimpleOp(opPop.offset, Opcode.from("POP").value) }} ]

    {{! setJumpTable(opMload, Opcode.from("MLOAD").value) }}
    @opMload:
        ; [ ... dstMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        mload($$)
        jump($increment)

    {{! setJumpTable(opMstore, Opcode.from("MSTORE").value) }}
    @opMstore:
        ; [ ... value, dstMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        mstore($$, $$)
        jump($increment)

    {{! setJumpTable(opMstore8, Opcode.from("MSTORE8").value) }}
    @opMstore8:
        ; [ ... value, dstMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        mstore8($$, $$)
        jump($increment)

    @opSload[ {{= getSimpleOp(opSload.offset, Opcode.from("SLOAD").value) }} ]
    @opSstore[ {{= getSimpleOp(opSstore.offset, Opcode.from("SSTORE").value) }} ]

    {{! setJumpTable(opJump, Opcode.from("JUMP").value) }}
    @opJump:
        ; [ ... target ]

        dup1()

        ; [ ... target, target ]

        ; Store the updated PC (we will die below if it is not a JUMPDEST)
        mstore({{= SLOT_PC }}, add(1, $$))

        ; Get the opcode at target
        shr(248, calldataload(add(mload({{= SLOT_BC_OFF }}), $$)))
        ; [ ... opcode ]

        ; If it is a JUMPDEST, continue (skipping increment). Otherwise, die
        jumpi($next, eq({{= Opcode.from("JUMPDEST").value }}, $$))
        jump($opInvalid)

    {{! setJumpTable(opJumpi, Opcode.from("JUMPI").value) }}
    @opJumpi:
        ; [ ... notZero, target ]
        swap1()
        jumpi($popIncrement, isZero($$))
        jump($opJump)

    {{! setJumpTable(opPc, Opcode.from("PC").value) }}
    @opPc:
        ; [ ... ]
        mload({{= SLOT_PC }})
        jump($increment)

    {{! setJumpTable(opMsize, Opcode.from("MSIZE").value) }}
    @opMsize:
        ; [ ... ]
        sub(msize, {{= SLOT_MEM_BASE }})
        jump($increment)

    @opGas[ {{= getSimpleOp(opGas.offset, Opcode.from("GAS").value) }} ]

    {{! setJumpTable(opJumpDest, Opcode.from("JUMPDEST").value) }}
    @opJumpDest:
        jump($increment)

    ;;;;;;;;;;;;;;;
    ;; Push Operations (0x60 - 0x7f)

    @opsPush[ {{= getPushOps(opsPush.offset) }} ]

    ;;;;;;;;;;;;;;;
    ;; Duplicate Operations (0x80 - 0x8f)

    @opsDuplicate[ {{= getSimpleOpRange(opsDuplicate.offset, 0x80, 0x8f) }} ]


    ;;;;;;;;;;;;;;;
    ;; Swap Operations (0x90 - 0x9f)

    @opsSwap[ {{= getSimpleOpRange(opsSwap.offset, 0x90, 0x9f) }} ]


    ;;;;;;;;;;;;;;;
    ;; Log Operations (0xa0 - 0xa4)

    @opLog0[ {{= getLogOp(opLog0.offset, Opcode.from("LOG0").value) }} ]
    @opLog1[ {{= getLogOp(opLog1.offset, Opcode.from("LOG1").value) }} ]
    @opLog2[ {{= getLogOp(opLog2.offset, Opcode.from("LOG2").value) }} ]
    @opLog3[ {{= getLogOp(opLog3.offset, Opcode.from("LOG3").value) }} ]
    @opLog4[ {{= getLogOp(opLog4.offset, Opcode.from("LOG4").value) }} ]


    ;;;;;;;;;;;;;;;
    ;; System Operations (0xf0 - 0xff, 0xfa, 0xfd - 0xff)

    {{! setJumpTable(opCreate, Opcode.from("CREATE").value) }}
    @opCreate:
        ; [ ... srcLength, srcOffset, value ]

        swap1()
        add(mload({{= SLOT_MEM }}), $$)
        swap1()

        create($$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCall, Opcode.from("CALL").value) }}
    @opCall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add(mload({{= SLOT_MEM }}), $$)
        swap3()

        swap5()
        add(mload({{= SLOT_MEM }}), $$)
        swap5()

        call($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCallcode, Opcode.from("CALLCODE").value) }}
    @opCallcode:
        ; @TODO: Is this correct? No good docs on CALLCODE...
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add(mload({{= SLOT_MEM }}), $$)
        swap3()

        swap5()
        add(mload({{= SLOT_MEM }}), $$)
        swap5()

        callcode($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opReturn, Opcode.from("RETURN").value) }}
    @opReturn:
        ; [ ... length, srcMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        return($$, $$)

    {{! setJumpTable(opDelegatecall, Opcode.from("DELEGATECALL").value) }}
    @opDelegatecall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add(mload({{= SLOT_MEM }}), $$)
        swap2()

        swap4()
        add(mload({{= SLOT_MEM }}), $$)
        swap4()

        delegatecall($$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCreate2, Opcode.from("CREATE2").value) }}
    @opCreate2:
        ; [ ... salt, srcLength, srcOffset, value ]

        swap1()
        add(mload({{= SLOT_MEM }}), $$)
        swap1()

        create2($$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opStaticcall, Opcode.from("STATICCALL").value) }}
    @opStaticcall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add(mload({{= SLOT_MEM }}), $$)
        swap2()

        swap4()
        add(mload({{= SLOT_MEM }}), $$)
        swap4()

        staticcall($$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opRevert, Opcode.from("REVERT").value) }}
    @opRevert:
        ; [ ... length, srcMemOffset ]
        add(mload({{= SLOT_MEM }}), $$)
        revert($$, $$)

    @opInvalid:
        invalid

    @opSuicide[ {{= getSimpleOp(opSuicide.offset, Opcode.from("SUICIDE").value) }} ]

    ;;;;
    ;;;; Anything after this can have 2-byte offsets
    ;;;;


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
        mstore({{= SLOT_BC_LEN }}, calldataload($$))    ; [ 0x04, bytecode_length ]
        add(32, $$)                                      ; [ 0x04, bytecode_data ]
        mstore({{= SLOT_BC_OFF }}, $$)                  ; [ 0x04 ]

        ; Memory
        ; Slot   Value
        ;  1      bytecode_offset
        ;  2      bytecode_length

        ; Load the calldata size and offset
        calldataload(0x24)                               ; [ 0x04, calldata_link ]
        add($$, $$)                                      ; [ calldata ]
        dup1()                                           ; [ calldata, calldata ]
        calldataload($$)                                 ; [ calldata, calldata.length ]
        swap1()                                          ; [ calldata.length, calldata ]
        add(32, $$)                                      ; [ calldata.length, calldata.data ]
        or(shl({{= CD_OFF_SHIFT }}, $$), $$)             ; [ (calldata.length | (calldata.data << CD_OFF_SHIFT)) ]
        mstore({{= SLOT_CD }}, $$)                       ; [ ]

        ;  3      calldata_offset
        ;  4      calldata_length

        mstore({{= SLOT_MEM }}, {{= SLOT_MEM_BASE }})

        ;  5      memory_base => 6

        ; Start exeuting the VM
        jump($next)


    ; The stack must be intact (from the virtualized environment's point
    ; of view) when entering this jump table.

    @operations[ {{= concat(jumpTable.map((e) => zeroPad(hexlify(e), 2))) }} ]

    {{!
        // Some sanity checking after the bytecode is stable
        // - Make sure every opcode is represented (jumps to a unique offset)
        // - Make sure all non-opcodes jump to invalid
        console.log("-------------")
        if (opInvalid) {
            const target = { };
            let lastOffset = 0;
            for (let i = 0; i < 256; i++) {
                let opcode = Opcode.from(i);
                const offset = jumpTable[i];
                //console.log(">", offset, opcode ? opcode.mnemonic: null);
                if (opcode === null) {
                    if (offset !== opInvalid) {
                        //throw new Error("INVALID jumps to valid operation");
                        console.log("INVALID jumps to valid operation");
                    }
                } else {
                    if (target[offset]) {
                        //throw new Error(`Duplicate ${ offset } for ${ target[offset].mnemonic }`);
                        console.log(`Duplicate ${ offset } for ${ target[offset].mnemonic }`);
                    }
                    target[offset] = opcode;
                    if (opcode.mnemonic !== "INVALID" && offset === opInvalid) {
                        //throw new Error("opcode not defined: " + opcode.mnemonic);
                        console.log("opcode not defined: " + opcode.mnemonic);
                    }
                }
            }
        }
    }}
}
