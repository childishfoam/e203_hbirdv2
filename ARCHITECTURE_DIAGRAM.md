# E203 Data Forwarding Architecture Diagram

## Pipeline Stages with Data Forwarding

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    E203 RISC-V Pipeline with Data Forwarding                │
└─────────────────────────────────────────────────────────────────────────────┘

     ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐
     │ IFU  │ ───► │ DEC  │ ───► │ DISP │ ───► │ ALU  │ ───► │ WB   │
     │Fetch │      │Decode│      │patch │      │ EXU  │      │Back  │
     └──────┘      └──────┘      └───┬──┘      └───┬──┘      └───┬──┘
                                     │             │             │
                                     │             │             │
                      ┌──────────────┼─────────────┼─────────────┘
                      │ Forwarding   │             │
                      │ Paths        │             │
                      ▼              ▼             │
                  ┌────────────────────────┐      │
                  │  Operand Selection     │      │
                  │  with Forwarding       │      │
                  │                        │      │
                  │  Priority:             │      │
                  │  1. ALU Writeback  ◄───┼──────┘
                  │  2. LongP Writeback◄───┼─────────┐
                  │  3. RegFile Read       │         │
                  └────────────────────────┘         │
                                                     │
                      ┌──────────────────────────────┘
                      │ Long-Pipe (Load/Store)
                      ▼
                  ┌───────┐
                  │ OITF  │
                  │Track  │
                  └───────┘
```

## Data Forwarding Paths Detail

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Forwarding Logic in DISP                        │
└─────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │  RF Read (rs1)  │
                    │  Default Path   │
                    └────────┬────────┘
                             │
                             ▼
    ┌────────────────────────────────────────────┐
    │         Operand Selection MUX              │
    │                                            │
    │    ALU_FWD?  ─────►  ALU Wbck Data        │
    │       │                                    │
    │       └─ No ─►  LongP_FWD? ──► LongP Data │
    │                     │                      │
    │                     └─ No ──► RF Data     │
    └──────────────────────┬───────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  rs1_data   │
                    │ to ALU EXU  │
                    └─────────────┘

Forwarding Conditions:
━━━━━━━━━━━━━━━━━━━
ALU_FWD_rs1  = (alu_wbck_valid) && 
               (alu_wbck_rdidx == disp_rs1idx) && 
               (alu_wbck_rdidx != 0)

LongP_FWD_rs1 = (longp_wbck_valid) && 
                (longp_wbck_rdidx == disp_rs1idx) && 
                (longp_wbck_rdidx != 0)
```

## Dependency Checking with Forwarding

```
┌─────────────────────────────────────────────────────────────────────┐
│              RAW Dependency Resolution Flow                          │
└─────────────────────────────────────────────────────────────────────┘

                 Instruction in DISP
                        │
                        ▼
            ┌───────────────────────┐
            │  Check OITF Match     │
            │  (Long-pipe pending)  │
            └──────────┬────────────┘
                       │
                       ▼
            ┌───────────────────────┐
            │   Can Forward?        │
            │   ALU or LongP WB     │
            └──┬─────────────────┬──┘
               │ YES             │ NO
               │                 │
               ▼                 ▼
        ┌──────────┐      ┌──────────┐
        │ Forward  │      │  Stall   │
        │ Proceed  │      │  Wait    │
        └──────────┘      └──────────┘
             │                  │
             └────────┬─────────┘
                      │
                      ▼
            ┌──────────────────┐
            │  Execute in ALU  │
            └──────────────────┘

BEFORE Forwarding:
  RAW Hazard → Always Stall → Lower Performance

AFTER Forwarding:
  RAW Hazard → Check Forward → Proceed if possible → Higher Performance
```

## Example: Instruction Sequence with Forwarding

```
Cycle   Instruction          Stage in Pipeline          Forwarding Action
────────────────────────────────────────────────────────────────────────
  1     addi x1, x0, 5       [IF|DEC|DISP|ALU|WB]      -
  2     addi x2, x0, 3       [IF|DEC|DISP|ALU|WB]      -
  3     add  x3, x1, x2      [IF|DEC|DISP|ALU|WB]      Forward x1,x2 from WB
  4     sw   x3, 0(x0)       [IF|DEC|DISP|ALU|WB]      Forward x3 from WB
  5     lw   x4, 0(x0)       [IF|DEC|DISP|AGU|..]      -
  6     ...                  [..|..|..|..|LSU]         Wait for load
  7     add  x5, x4, x1      [IF|DEC|DISP|ALU|WB]      Forward x4 from LongP WB
  8     sub  x6, x5, x2      [IF|DEC|DISP|ALU|WB]      Forward x5 from WB

Without Forwarding:
  Cycle 3: STALL (wait for x1, x2)
  Cycle 4: STALL (wait for x3)
  Cycle 7: STALL (wait for x4)
  Cycle 8: STALL (wait for x5)
  
With Forwarding:
  Cycle 3: NO STALL (forward x1, x2)
  Cycle 4: NO STALL (forward x3)
  Cycle 7: NO STALL (forward x4)
  Cycle 8: NO STALL (forward x5)
  
Cycles Saved: ~4 cycles (20% improvement for this sequence)
```

## Testbench Monitoring Output Format

```
═══════════════════════════════════════════════════════════════════
                    HAZARD TEST EXECUTION
═══════════════════════════════════════════════════════════════════

[HAZARD_TEST] Instruction 1: addi x1, x0, 5  | Cycle: 100 | x1=00000005
[HAZARD_TEST] Instruction 2: addi x2, x0, 3  | Cycle: 101 | x2=00000003
[HAZARD_TEST] Instruction 3: add  x3, x1, x2 | Cycle: 102 | x3=00000008
[HAZARD_TEST] Instruction 4: sw   x3, 0(x0)  | Cycle: 103
[HAZARD_TEST] Instruction 5: lw   x4, 0(x0)  | Cycle: 104 | x4=00000008
[HAZARD_TEST] Instruction 6: add  x5, x4, x1 | Cycle: 107 | x5=0000000D
[HAZARD_TEST] Instruction 7: sub  x6, x5, x2 | Cycle: 108 | x6=0000000A
[HAZARD_TEST] Instruction 8: mul  x7, x6, x3 | Cycle: 109 | x7=00000050
[HAZARD_TEST] Instruction 9: addi x1, x0, 8  | Cycle: 112 | x1=00000008
[HAZARD_TEST] Instruction 10: add  x8, x7, x1 | Cycle: 113 | x8=00000058
[HAZARD_TEST] Instruction 11: and  x9, x8, x5 | Cycle: 114 | x9=00000008
[HAZARD_TEST] Instruction 12: or   x10,x9, x7 | Cycle: 115 | x10=00000058
[HAZARD_TEST] Instruction 13: xor  x11,x10,x8 | Cycle: 116 | x11=00000000
[HAZARD_TEST] Instruction 14: sll  x12,x11,x2 | Cycle: 117 | x12=00000000
[HAZARD_TEST] Instruction 15: srl  x13,x12,x1 | Cycle: 118 | x13=00000000
[HAZARD_TEST] Instruction 16: addi x14,x13,-1 | Cycle: 119 | x14=FFFFFFFF
[HAZARD_TEST] Instruction 17: sw   x14,4(x0)  | Cycle: 120
[HAZARD_TEST] Instruction 18: lw   x15,4(x0)  | Cycle: 121 | x15=FFFFFFFF
[HAZARD_TEST] Instruction 19: add  x16,x15,x10| Cycle: 124 | x16=00000057
[HAZARD_TEST] Instruction 20: mul  x17,x16,x13| Cycle: 125 | x17=00000000

========== HAZARD TEST COMPLETED ==========
Total cycles for 20 instructions: 26
===========================================

Comparison (hypothetical):
  Without Forwarding: ~35 cycles
  With Forwarding:    ~26 cycles
  Improvement:        25.7%
```

## Module Hierarchy with Forwarding

```
e203_exu
├── e203_exu_regfile
│   └── Register File (32 registers)
│
├── e203_exu_decode
│   └── Instruction Decoder
│
├── e203_exu_disp  ◄─── MODIFIED: Added Forwarding Logic
│   ├── Dependency Checker (updated)
│   ├── Forwarding Detection (NEW)
│   ├── Operand Selection MUX (NEW)
│   └── Dispatch Control
│
├── e203_exu_oitf
│   └── Outstanding Instruction Tracker
│
├── e203_exu_alu
│   ├── ALU Datapath
│   ├── BJP Unit
│   ├── AGU (Load/Store)
│   └── MULDIV (optional)
│
├── e203_exu_wbck  ◄─── Forwarding Source
│   ├── ALU Writeback ────► Forwarding to DISP
│   └── LongP Writeback ──► Forwarding to DISP
│
└── e203_exu_commit
    └── Commit Logic
```

## Performance Impact Summary

```
┌────────────────────────────────────────────────────────────────┐
│             Performance Improvement Estimation                  │
└────────────────────────────────────────────────────────────────┘

Hazard Type          Without FWD    With FWD    Improvement
─────────────────────────────────────────────────────────────
ALU-ALU RAW          2 stall        0 stall     100%
ALU-Load RAW         2 stall        0 stall     100%
Load-ALU RAW         3 stall        0-1 stall   66-100%
Store-Load WAR       0 stall        0 stall     N/A

Overall Performance:
  Compute-intensive:  20-30% cycle reduction
  Memory-intensive:   10-15% cycle reduction  
  Mixed workload:     15-20% cycle reduction

Clock Impact:
  Critical path increase: < 5%
  Area increase: < 2%
  Power increase: < 3%
```

Legend:
  IF  = Instruction Fetch
  DEC = Decode
  DISP = Dispatch
  ALU = Arithmetic Logic Unit
  WB  = Writeback
  RF  = Register File
  OITF = Outstanding Instruction Track FIFO
  FWD = Forwarding
  RAW = Read After Write
  WAR = Write After Read
  WAW = Write After Write
