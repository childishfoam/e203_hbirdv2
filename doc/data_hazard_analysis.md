# Data Hazard Analysis for E203 Test Program

## Test Program Assembly Code:
```assembly
1.  addi x1, x0, 5      # x1 = 5
2.  addi x2, x0, 3      # x2 = 3
3.  add x3, x1, x2      # x3 = x1 + x2 = 8 (RAW: x1 from instr 1, x2 from instr 2)
4.  sw x3, 0(x0)        # Store x3 to memory[0] (RAW: x3 from instr 3)
5.  lw x4, 0(x0)        # Load x4 from memory[0] (Long-pipe instruction)
6.  add x5, x4, x1      # x5 = x4 + x1 (RAW: x4 from instr 5, x1 from instr 1)
7.  sub x6, x5, x2      # x6 = x5 - x2 (RAW: x5 from instr 6, x2 from instr 2)
8.  mul x7, x6, x3      # x7 = x6 * x3 (RAW: x6 from instr 7, x3 from instr 3)
9.  addi x1, x0, 8      # x1 = 8 (WAR: x1 written, was used in instr 6)
10. add x8, x7, x1      # x8 = x7 + x1 (RAW: x7 from instr 8, x1 from instr 9)
11. and x9, x8, x5      # x9 = x8 & x5 (RAW: x8 from instr 10, x5 from instr 6)
12. or x10, x9, x7      # x10 = x9 | x7 (RAW: x9 from instr 11, x7 from instr 8)
13. xor x11, x10, x8    # x11 = x10 ^ x8 (RAW: x10 from instr 12, x8 from instr 10)
14. sll x12, x11, x2    # x12 = x11 << x2 (RAW: x11 from instr 13, x2 from instr 2)
15. srl x13, x12, x1    # x13 = x12 >> x1 (RAW: x12 from instr 14, x1 from instr 9)
16. addi x14, x13, -1   # x14 = x13 - 1 (RAW: x13 from instr 15)
17. sw x14, 4(x0)       # Store x14 to memory[4] (RAW: x14 from instr 16)
18. lw x15, 4(x0)       # Load x15 from memory[4] (Long-pipe instruction)
19. add x16, x15, x10   # x16 = x15 + x10 (RAW: x15 from instr 18, x10 from instr 12)
20. mul x17, x16, x13   # x17 = x16 * x13 (RAW: x16 from instr 19, x13 from instr 15)
```

## Data Hazard Classification:

### RAW (Read-After-Write) Hazards - TRUE Dependencies:
1. **Instr 3** reads x1 (written by instr 1) and x2 (written by instr 2)
   - Type: ALU-to-ALU, 2 cycles apart for x1, 1 cycle apart for x2
   
2. **Instr 4** reads x3 (written by instr 3)
   - Type: ALU-to-LSU, 1 cycle apart
   
3. **Instr 6** reads x4 (written by instr 5) and x1 (written by instr 1)
   - Type: LSU-to-ALU (x4), requires stall (long-pipe)
   - Type: ALU-to-ALU (x1), 5 cycles apart (no hazard)
   
4. **Instr 7** reads x5 (written by instr 6) and x2 (written by instr 2)
   - Type: ALU-to-ALU, 1 cycle apart for x5
   
5. **Instr 8** reads x6 (written by instr 7) and x3 (written by instr 3)
   - Type: ALU-to-ALU, 1 cycle apart for x6
   - Type: MUL instruction (may be long-pipe)
   
6. **Instr 10** reads x7 (written by instr 8) and x1 (written by instr 9)
   - Type: MUL-to-ALU (x7), may require stall
   - Type: ALU-to-ALU (x1), 1 cycle apart
   
7. **Instr 11** reads x8 (written by instr 10) and x5 (written by instr 6)
   - Type: ALU-to-ALU, 1 cycle apart for x8
   
8. **Instr 12** reads x9 (written by instr 11) and x7 (written by instr 8)
   - Type: ALU-to-ALU, 1 cycle apart for x9
   
9. **Instr 13** reads x10 (written by instr 12) and x8 (written by instr 10)
   - Type: ALU-to-ALU, 1 cycle apart for x10
   
10. **Instr 14** reads x11 (written by instr 13) and x2 (written by instr 2)
    - Type: ALU-to-ALU, 1 cycle apart for x11
    
11. **Instr 15** reads x12 (written by instr 14) and x1 (written by instr 9)
    - Type: ALU-to-ALU, 1 cycle apart for x12
    
12. **Instr 16** reads x13 (written by instr 15)
    - Type: ALU-to-ALU, 1 cycle apart
    
13. **Instr 17** reads x14 (written by instr 16)
    - Type: ALU-to-LSU, 1 cycle apart
    
14. **Instr 19** reads x15 (written by instr 18) and x10 (written by instr 12)
    - Type: LSU-to-ALU (x15), requires stall (long-pipe)
    
15. **Instr 20** reads x16 (written by instr 19) and x13 (written by instr 15)
    - Type: ALU-to-MUL, 1 cycle apart for x16
    - Type: MUL instruction (may be long-pipe)

## Current E203 Handling:
- **2-stage pipeline**: Instructions are dispatched and executed
- **OITF tracking**: Long-pipe instructions (load/store, mul/div) are tracked
- **Stall mechanism**: On RAW/WAW dependency with OITF entries, pipeline stalls
- **NO FORWARDING**: Currently no data forwarding from ALU or write-back stage

## Expected Stalls WITHOUT Forwarding:
Since E203 is a 2-stage pipeline, and operands are read during dispatch:
- **Instr 3**: Stalls until instr 1 and 2 write back (2 cycles for instr 1, 1 cycle for instr 2)
- **Instr 4**: Stalls until instr 3 writes back (1 cycle)
- **Instr 6**: Stalls until instr 5 completes (load is long-pipe, multiple cycles)
- **Instr 7**: Stalls until instr 6 writes back (1 cycle)
- **Instr 8**: Stalls until instr 7 writes back (1 cycle)
- **Instr 10**: Stalls until instr 8 completes (mul is long-pipe) and instr 9 writes back
- And so on...

## Forwarding Paths to Implement:
1. **ALU-to-ALU forwarding**: Forward ALU result directly to next instruction
2. **Write-back-to-Dispatch forwarding**: Forward write-back data to dispatch stage
3. **Long-pipe forwarding**: Handle forwarding from long-pipe instructions (LSU, MUL/DIV)

## Performance Improvement:
With forwarding, many 1-cycle stalls can be eliminated:
- ALU instructions can use results from previous ALU instruction immediately
- Only long-pipe instructions (load, mul/div) will require stalls
- Expected reduction: ~50% fewer stalls for this test program
