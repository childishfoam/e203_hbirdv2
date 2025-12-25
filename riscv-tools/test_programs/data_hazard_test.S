# Data Hazard Test Program for E203 Forwarding Mechanism
# This test program contains various RAW hazards to test the data forwarding implementation

.section .text
.global _start

_start:
    # Initialize registers
    li x1, 5          # x1 = 5 (addi x1, x0, 5)
    li x2, 3          # x2 = 3 (addi x2, x0, 3)
    
    # Test 1: ALU-to-ALU forwarding (immediate dependency)
    add x3, x1, x2    # x3 = x1 + x2 = 8 (RAW: x1 from prev, x2 from prev)
    sw x3, 0(x0)      # Store x3 to memory[0] (RAW: x3 from prev)
    
    # Test 2: Load-to-ALU dependency (requires stall, no forwarding)
    lw x4, 0(x0)      # Load x4 from memory[0] (long-pipe)
    add x5, x4, x1    # x5 = x4 + x1 (RAW: x4 from load, x1 from earlier)
    
    # Test 3: Consecutive ALU operations (forwarding chain)
    sub x6, x5, x2    # x6 = x5 - x2 (RAW: x5 from prev)
    mul x7, x6, x3    # x7 = x6 * x3 (RAW: x6 from prev, may be long-pipe)
    
    # Test 4: Register reuse (x1 written again)
    li x1, 8          # x1 = 8 (addi x1, x0, 8)
    add x8, x7, x1    # x8 = x7 + x1 (RAW: x7 from mul, x1 from immediate prev)
    
    # Test 5: Multiple dependencies
    and x9, x8, x5    # x9 = x8 & x5 (RAW: x8 from prev)
    or x10, x9, x7    # x10 = x9 | x7 (RAW: x9 from prev)
    xor x11, x10, x8  # x11 = x10 ^ x8 (RAW: x10 from prev)
    
    # Test 6: Shift operations
    sll x12, x11, x2  # x12 = x11 << x2 (RAW: x11 from prev)
    srl x13, x12, x1  # x13 = x12 >> x1 (RAW: x12 from prev)
    
    # Test 7: Store with dependency
    addi x14, x13, -1 # x14 = x13 - 1 (RAW: x13 from prev)
    sw x14, 4(x0)     # Store x14 to memory[4] (RAW: x14 from prev)
    
    # Test 8: Another load-to-ALU dependency
    lw x15, 4(x0)     # Load x15 from memory[4] (long-pipe)
    add x16, x15, x10 # x16 = x15 + x10 (RAW: x15 from load)
    
    # Test 9: Final multiplication
    mul x17, x16, x13 # x17 = x16 * x13 (RAW: x16 from prev)
    
    # Test completion marker
    li x18, 0xDEAD
    li x19, 0xBEEF
    
    # Success: jump to infinite loop
    j _success

_success:
    # Store success pattern to memory
    li x20, 0x600D
    sw x20, 8(x0)
    j _success

# Data section (if needed)
.section .data
test_data:
    .word 0x0
    .word 0x0
    .word 0x0
