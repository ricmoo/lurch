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
        

    @increment:
        ; Increment the PC by 1
        mstore({{= slot(PC) }}, add(mload({{= slot(PC) }}), 1))

        ; falls-through

    @next:
        ; Get the current PC
        mload({{= slot(PC) }})

        ; [ PC ]

        ; Get the current operation
        shr(248, calldataload(add(mload({{= slot(BC_OFF) }}), $$)))

        ; [ opcode ]

        ; Get the operation jump destination
        add($operations, mul(6, $$))

        ; [ jump_dest ]

        jump($$)

    @returnOp:
       ;; TEMP -debug remove the range
        pop()
        pop()

        ;;; DEBUG
        dup1()
        mstore({{= slot(PC) }}, $$)
        return(0, {{= 32 * 8 }})
        ;;; /DEBUG

    @invalidOp:

        ; @TODO
        mstore({{= slot(PC) }}, 0xdeadbeef)
        return(0, 32)
    
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

        ; Start exeuting the VM
        jump($next)


    ; Create an addressable jump destination block

    ; This table keeps all instructions at 6 bytes each, so a given
    ; operation can be found at ($operations + 6 * opcode). Any complex
    ; opcodes need to jump to an additional location for extra logic.

    ; The stack must be intact (from the virtualized environment's point
    ; of view) when entering this jump table.

    {{!
        const code = [ ];
        let lastLength = 2;
        for (let i = 0; i < 256; i++) {
            let opcode = Opcode.from(i);

            if (opcode == null) {
                // Trap Invalid opcodes for possible reporting
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(Opcode.from("PUSH2"));                  // 1 byte
                code.push(zeroPad(hexlify(invalidOp), 2));        // 2 bytes
                code.push(Opcode.from("JUMP"));                   // 1 byte                
                code.push(Opcode.from("STOP"));                   // 1 byte
            
            } else if (opcode.isPush()) {
                // PUSH opcodes include their push count on the stack
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(opcode.isPush()), 1));  // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(pushOp), 1));           // 1 byte
                code.push(Opcode.from("JUMP"));                   // 1 byte                

            } else if (opcode.mnemonic === "RETURN") {
                // Return is hijacked for now for testing...
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(Opcode.from("PUSH2"));                  // 1 byte
                code.push(zeroPad(hexlify(returnOp), 2));         // 2 bytes
                code.push(Opcode.from("JUMP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
            
            } else {
                // Most things just work with the stack
                code.push(Opcode.from("JUMPDEST"));               // 1 byte
                code.push(opcode);                                // 1 byte
                code.push(Opcode.from("PUSH1"));                  // 1 byte
                code.push(zeroPad(hexlify(increment), 1));        // 1 bytes
                code.push(Opcode.from("JUMP"));                   // 1 byte
                code.push(Opcode.from("STOP"));                   // 1 byte
            }

            if (concat(code).length !== lastLength + 12) {
                console.log(concat(code).length, lastLength, code);
                throw new Error("wrong bytecode length for jump table: " + i);
            }
            lastLength = concat(code).length;
        }
    }}

    @operations[ {{= concat(code) }} ]
}
