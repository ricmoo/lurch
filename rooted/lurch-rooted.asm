; Lurch VM (rooted.eth)
;
; This Lurch VM is redesigned (slightly) to work with rooted.eth,
; which makes Wisp creation easier by attaching a single address
; to a given creator.
;
; The calldata layout for this Lurch is:
;   [ caller: 32 bytes ] [ bytecode length: 32 bytes ] [ bytecode: XX bytes ]

; Memory Layout
; Slot   Purpose
;  0      PC             (adjusted for calldata offset)
;  1      End offset     (adjusted for calldata offset)
;  2      Scratch
;  3      ... Virtualized Memory starts here ...
;

{{!

    const SLOT_PC        = 0x00;
    const SLOT_BC_END    = 0x20;

    // The offset (in bytes) into SLOT_CD where the left
    // edge of the SCRATCH begins.
    const SLOT_SCRATCH   = 0x40;

    const SLOT_MEM_BASE  = 0x60;

    // [ caller: 32 bytes ] [ bytecode.length: 32 bytes ] [ bytecode: XX bytes ]
    const CD_CALLER_OFFSET     = 0
    const CD_BC_LENGTH_OFFSET  = 32;
    const CD_BC_OFFSET         = 64;

}}


; Deployment initcode (we copy everything including this bootstrap
; so the offsets are easier to work with for replacing placeholders)
codecopy(0, $_, #_)

; Inject my real address into the contract (overwrite the PUSH32)
mstore({{= myAddress.offset + 1 }}, address)

; Return the Lurch Contract
return($Lurch, #Lurch)


@Lurch {
    ; Make sure we are in a DELEGATECALL

    ; Put my real address here at deployment(to detect if in a call delegate)
    @myAddress[ ]
    {{= zeroPad(0, 32) }}

    ; if address != myAddress: start
    jumpi($start, sub(address, $$))

    ; DEBUG
    ;jump($start)

    ; Error! Not in a DELEGATECALL
    revert(0, 0)

    @popIncrement:
        ; [ ... target ]

        ; Clean up the stack from a JUMPI
        pop()

        ; ... falls-through ...

    @increment:
        ; Increment the PC by 1
        mstore({{= SLOT_PC }}, add(mload({{= SLOT_PC }}), 1))

        ; ... falls-through ...

    @next:
        ; The length below for the codecopy to fetch the jumpdest
        0x02

        ; Get the current PC (adjusted to calldata)
        mload({{= SLOT_PC }})

        ; [ 0x02, PC ]

        ; Bounds checking; compute a multiplier (0 if out-of-bounds, 1 otherwise)
        lt(dup2(), mload({{= SLOT_BC_END }}))
        swap1()

        ; [ 0x02, ((PC < BC_LEN) ? 1: 0), PC ]

        ; Get the current operation
        shr(248, calldataload($$))

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
            ops.push(SLOT_MEM_BASE);
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
        ; [ ... length, memDestOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
        sha3($$, $$)
        jump($increment)


    ;;;;;;;;;;;;;;;
    ;; Environment Information (0x30 - 0x3f)

    @opAddress[ {{= getSimpleOp(opAddress.offset, Opcode.from("ADDRESS").value) }} ]
    @opBalance[ {{= getSimpleOp(opBalance.offset, Opcode.from("BALANCE").value) }} ]
    @opOrigin[ {{= getSimpleOp(opOrigin.offset, Opcode.from("ORIGIN").value) }} ]

    {{! setJumpTable(opCaller, Opcode.from("CALLER").value) }}
    @opCaller:
       ; [ ... ]
        calldataload({{= CD_CALLER_OFFSET }})
        jump($increment)

    @opCallvalue[ {{= getSimpleOp(opCallvalue.offset, Opcode.from("CALLVALUE").value) }} ]

    {{! setJumpTable(opCalldataload, Opcode.from("CALLDATALOAD").value) }}
    @opCalldataload:
        ; [ ... offset ]
        0x00
        jump($increment)

    {{! setJumpTable(opCalldatasize, Opcode.from("CALLDATASIZE").value) }}
    @opCalldatasize:
        ; [ ... ]
        0x00
        jump($increment)

    {{! setJumpTable(opCalldatacopy, Opcode.from("CALLDATACOPY").value) }}
    @opCalldatacopy:
        ; [ ... length, offset, dstMemOffset ]

        ; This version of Lurch does not support calldata, so it
        ; fast-forwards to thhe end of the actual calldata to
        ; zero-fill the output

        calldatasize()       ; [ ... length, offset, dstMemOffset, calldatasize ]
        swap2()              ; [ ... length, calldatasize, dstMemOffset, offset ]
        pop()                ; [ ... length, calldatasize, dstMemOffset ]

        ; [ ... length, calldatasize, dstMemOffset ]

        add({{= SLOT_MEM_BASE }}, $$)
        calldatacopy($$, $$, $$)
        jump($increment)

    {{! setJumpTable(opCodesize, Opcode.from("CODESIZE").value) }}
    @opCodesize:
        ; [ ... ]
        calldataload({{= CD_BC_LENGTH_OFFSET }})
        jump($increment)

    {{! setJumpTable(opCodecopy, Opcode.from("CODECOPY").value) }}
    @opCodecopy:
        ; [ ... length, offset, dstMemOffset]
        add({{= SLOT_MEM_BASE }}, $$)

        swap1()
        add({{= CD_BC_OFFSET }}, $$)
        swap1()
        calldatacopy($$, $$, $$)
        jump($increment)

    @opGasprice[ {{= getSimpleOp(opGasprice.offset, Opcode.from("GASPRICE").value) }} ]
    @opExtcodesize[ {{= getSimpleOp(opExtcodesize.offset, Opcode.from("EXTCODESIZE").value) }} ]

    {{! setJumpTable(opExtcodecopy, Opcode.from("EXTCODECOPY").value) }}
    @opExtcodecopy:
        ; [ ... length, offset, dstMemOffset, address]
        swap1()
        add({{= SLOT_MEM_BASE }}, $$)
        swap1()
        extcodecopy($$, $$, $$, $$)
        jump($increment)

    @opReturndatasize[ {{= getSimpleOp(opReturndatasize.offset, Opcode.from("RETURNDATASIZE").value) }} ]

    ; needs call to test...
    {{! setJumpTable(opReturndatacopy, Opcode.from("RETURNDATACOPY").value) }}
    @opReturndatacopy:
        ; [ ... length, offset, dstMemOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
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
        add({{= SLOT_MEM_BASE }}, $$)
        mload($$)
        jump($increment)

    {{! setJumpTable(opMstore, Opcode.from("MSTORE").value) }}
    @opMstore:
        ; [ ... value, dstMemOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
        mstore($$, $$)
        jump($increment)

    {{! setJumpTable(opMstore8, Opcode.from("MSTORE8").value) }}
    @opMstore8:
        ; [ ... value, dstMemOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
        mstore8($$, $$)
        jump($increment)

    @opSload[ {{= getSimpleOp(opSload.offset, Opcode.from("SLOAD").value) }} ]
    @opSstore[ {{= getSimpleOp(opSstore.offset, Opcode.from("SSTORE").value) }} ]

    {{! setJumpTable(opJump, Opcode.from("JUMP").value) }}
    @opJump:
        ; [ ... target ]
        add({{= CD_BC_OFFSET }}, $$)

        dup1()

        ; [ ... target, target ]

        ; Store the updated PC (we will die below if it is not a JUMPDEST)
        mstore({{= SLOT_PC }}, add(1, $$))

        ; Get the opcode at target
        ;shr(248, calldataload(add(mload({{= SLOT_BC_OFF }}), $$)))
        shr(248, calldataload($$))
        ; [ ... opcode ]

        ; If it is a JUMPDEST, continue (skipping increment). Otherwise, die
        jumpi($next, eq({{= Opcode.from("JUMPDEST").value }}, $$))
        jump($opInvalid)

    {{! setJumpTable(opJumpi, Opcode.from("JUMPI").value) }}
    @opJumpi:
        ; [ ... notZero, target ]
        swap1()
        jumpi($popIncrement, isZero($$))

        ;jump($opJump)

        ; [ ... target ]
        add({{= CD_BC_OFFSET }}, $$)

        dup1()

        ; [ ... target, target ]

        ; Store the updated PC (we will die below if it is not a JUMPDEST)
        mstore({{= SLOT_PC }}, add(1, $$))

        ; Get the opcode at target
        ;shr(248, calldataload(add(mload({{= SLOT_BC_OFF }}), $$)))
        shr(248, calldataload($$))
        ; [ ... opcode ]

        ; If it is a JUMPDEST, continue (skipping increment). Otherwise, die
        jumpi($next, eq({{= Opcode.from("JUMPDEST").value }}, $$))
        jump($opInvalid)

    {{! setJumpTable(opPc, Opcode.from("PC").value) }}
    @opPc:
        ; [ ... ]
        sub(mload({{= SLOT_PC }}), {{= CD_BC_OFFSET }})
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
        add({{= SLOT_MEM_BASE }}, $$)
        swap1()

        create($$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCall, Opcode.from("CALL").value) }}
    @opCall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add({{= SLOT_MEM_BASE }}, $$)
        swap3()

        swap5()
        add({{= SLOT_MEM_BASE }}, $$)
        swap5()

        call($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCallcode, Opcode.from("CALLCODE").value) }}
    @opCallcode:
        ; @TODO: Is this correct? No good docs on CALLCODE...
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, value, address, gasLimit ]

        swap3()
        add({{= SLOT_MEM_BASE }}, $$)
        swap3()

        swap5()
        add({{= SLOT_MEM_BASE }}, $$)
        swap5()

        callcode($$, $$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opReturn, Opcode.from("RETURN").value) }}
    @opReturn:
        ; [ ... length, srcMemOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
        return($$, $$)

    {{! setJumpTable(opDelegatecall, Opcode.from("DELEGATECALL").value) }}
    @opDelegatecall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add({{= SLOT_MEM_BASE }}, $$)
        swap2()

        swap4()
        add({{= SLOT_MEM_BASE }}, $$)
        swap4()

        delegatecall($$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opCreate2, Opcode.from("CREATE2").value) }}
    @opCreate2:
        ; [ ... salt, srcLength, srcOffset, value ]

        swap1()
        add({{= SLOT_MEM_BASE }}, $$)
        swap1()

        create2($$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opStaticcall, Opcode.from("STATICCALL").value) }}
    @opStaticcall:
        ; [ ... dstLength, dstMemOffset, srcLength, srcMemOffset, address, gasLimit ]

        swap2()
        add({{= SLOT_MEM_BASE }}, $$)
        swap2()

        swap4()
        add({{= SLOT_MEM_BASE }}, $$)
        swap4()

        staticcall($$, $$, $$, $$, $$, $$)

        jump($increment)

    {{! setJumpTable(opRevert, Opcode.from("REVERT").value) }}
    @opRevert:
        ; [ ... length, srcMemOffset ]
        add({{= SLOT_MEM_BASE }}, $$)
        revert($$, $$)

    @opInvalid:
        invalid

    @opSuicide[ {{= getSimpleOp(opSuicide.offset, Opcode.from("SUICIDE").value) }} ]


    ;;;;
    ;;;; Start the VM
    ;;;;

    @start:
        ; Initial PC (offset adjusted for calldata)
        mstore(0, {{= CD_BC_OFFSET }})

        ; End offset for the bytecode
        mstore({{= SLOT_BC_END }}, add(calldataload({{= CD_BC_LENGTH_OFFSET }}), {{= CD_BC_OFFSET }}));

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
