# Data Forwarding Implementation for E203 RISC-V Processor

## Overview
This document describes the implementation of data forwarding (data bypassing) mechanism in the Hummingbird E203 RISC-V processor to handle data hazards and improve performance.

## Implementation Summary

### 1. Architecture Changes

#### Modified Files:
- `rtl/e203/core/e203_exu_disp.v` - Dispatch module with forwarding logic
- `rtl/e203/core/e203_exu.v` - EXU module with forwarding connections
- `tb/tb_top.v` - Testbench with instruction monitoring
- `riscv-tools/riscv-tests/isa/rv32ui/hazard_test.S` - Test program with data hazards

### 2. Data Forwarding Logic

#### Forwarding Paths:
1. **ALU-to-Dispatch Forwarding**: Data from ALU writeback stage can be forwarded directly to dispatch stage
2. **Long-pipe-to-Dispatch Forwarding**: Data from load/store operations can be forwarded when available

#### Key Features:
- Forwarding detects when writeback data matches source operand registers
- Priority: ALU forwarding > Long-pipe forwarding > Register file
- Dependency checking updated to account for forwarded data
- RAW hazards are resolved through forwarding instead of pipeline stalls

### 3. Implementation Details

#### In `e203_exu_disp.v`:
```verilog
// Added forwarding inputs from writeback stages
input  alu_wbck_i_valid,
input  [`E203_XLEN-1:0] alu_wbck_i_wdat,
input  [`E203_RFIDX_WIDTH-1:0] alu_wbck_i_rdidx,

input  longp_wbck_i_valid,
input  [`E203_XLEN-1:0] longp_wbck_i_wdat,
input  [`E203_RFIDX_WIDTH-1:0] longp_wbck_i_rdidx,

// Forwarding detection logic
wire alu_fwd_rs1 = alu_wbck_i_valid & disp_i_rs1en & 
                   (alu_wbck_i_rdidx == disp_i_rs1idx) & 
                   (alu_wbck_i_rdidx != 0);

// Forwarding data selection
wire [`E203_XLEN-1:0] fwd_rs1_dat = alu_fwd_rs1 ? alu_wbck_i_wdat : 
                                    longp_fwd_rs1 ? longp_wbck_i_wdat : 
                                    disp_i_rs1;

// Updated dependency checking
wire oitfrd_match_disprs1_no_fwd = oitfrd_match_disprs1 & ~(alu_fwd_rs1 | longp_fwd_rs1);
wire raw_dep = (oitfrd_match_disprs1_no_fwd) | (oitfrd_match_disprs2_no_fwd) | ...;
```

### 4. Test Program

The test program (`hazard_test.S`) contains 20 instructions designed to test various data hazard scenarios:

1. `addi x1, x0, 5` - Initialize x1
2. `addi x2, x0, 3` - Initialize x2
3. `add x3, x1, x2` - RAW hazard on x1, x2
4. `sw x3, 0(x0)` - RAW hazard on x3
5. `lw x4, 0(x0)` - Load instruction (long-pipe)
6. `add x5, x4, x1` - Load-use hazard on x4
7. `sub x6, x5, x2` - RAW hazard on x5
8. `mul x7, x6, x3` - RAW hazard on x6
9. `addi x1, x0, 8` - WAW hazard on x1
10. `add x8, x7, x1` - RAW hazard on x7, x1
11. `and x9, x8, x5` - RAW hazard on x8
12. `or x10, x9, x7` - RAW hazard on x9
13. `xor x11, x10, x8` - RAW hazard on x10
14. `sll x12, x11, x2` - RAW hazard on x11
15. `srl x13, x12, x1` - RAW hazard on x12
16. `addi x14, x13, -1` - RAW hazard on x13
17. `sw x14, 4(x0)` - RAW hazard on x14
18. `lw x15, 4(x0)` - Load instruction (long-pipe)
19. `add x16, x15, x10` - Load-use hazard on x15
20. `mul x17, x16, x13` - RAW hazard on x16

### 5. Testbench Enhancements

The testbench (`tb_top.v`) has been enhanced with:
- Instruction tracking for the 20 test instructions
- Cycle counter for each instruction
- Register value printing after each instruction completion
- Total cycle count reporting

#### Output Format:
```
[HAZARD_TEST] Instruction 1: addi x1, x0, 5  | Cycle: XXX | x1=00000005
[HAZARD_TEST] Instruction 2: addi x2, x0, 3  | Cycle: XXX | x2=00000003
...
========== HAZARD TEST COMPLETED ==========
Total cycles for 20 instructions: XXX
===========================================
```

## How to Test

### Prerequisites:
1. RISC-V toolchain (nuclei_riscv_newlibc_prebuilt_linux64_2020.08 or compatible)
2. iverilog simulator
3. E203 repository cloned

### Steps:

#### 1. Set up toolchain (as per problem statement):
```bash
mkdir -p ./riscv-tools/prebuilt_tools/prefix/bin
cd ./riscv-tools/prebuilt_tools/prefix/bin/
ln -s ~/nuclei_riscv_newlibc_prebuilt_linux64_2020.08/gcc/bin/* .
cd ../../../../
```

#### 2. Compile the test program:
```bash
cd riscv-tools/riscv-tests/isa
source regen.sh
```

This will generate:
- `generated/rv32ui-p-hazard_test` - Executable
- `generated/rv32ui-p-hazard_test.dump` - Disassembly
- `generated/rv32ui-p-hazard_test.verilog` - Memory image for simulation

#### 3. Run simulation (baseline - without forwarding):
To test baseline performance, you can disable forwarding by commenting out the forwarding logic in `e203_exu_disp.v`.

```bash
cd vsim
make clean
make install
make compile SIM=iverilog
make run_test TESTCASE=../riscv-tools/riscv-tests/isa/generated/rv32ui-p-hazard_test DUMPWAVE=0
```

#### 4. Run simulation (with forwarding enabled):
```bash
cd vsim
make clean
make install
make compile SIM=iverilog
make run_test TESTCASE=../riscv-tools/riscv-tests/isa/generated/rv32ui-p-hazard_test DUMPWAVE=0
```

#### 5. Compare results:
Compare the cycle counts from baseline vs. forwarding-enabled runs to measure performance improvement.

## Expected Results

### Without Forwarding:
- Pipeline stalls on every RAW hazard
- Higher cycle count per instruction
- Load-use hazards cause additional stalls

### With Forwarding:
- Many RAW hazards resolved without stalling
- Reduced cycle count (estimated 20-30% improvement)
- Only load-use hazards may still cause stalls (depending on timing)
- Better instruction throughput

## Technical Notes

### Forwarding Priority:
1. ALU writeback (highest priority - most recent)
2. Long-pipe writeback (load/store completion)
3. Register file read (no forwarding needed)

### Special Cases:
- Register x0 is never forwarded (always zero)
- Forwarding only occurs when destination register matches source register
- OITF (Outstanding Instruction Track FIFO) still tracks long-pipeline instructions

### Performance Considerations:
The forwarding logic adds minimal critical path delay:
- Forwarding detection: Register index comparison (parallel with dependency check)
- Data multiplexing: 2-to-1 or 3-to-1 mux (depending on priority)
- The logic is designed to not impact the clock frequency significantly

## Future Enhancements

Possible improvements:
1. Add forwarding from commit stage for even later availability
2. Implement speculative forwarding for predicted branches
3. Add bypass network visualization in waveform viewer
4. Extend forwarding to handle FPU instructions (if E203_HAS_FPU enabled)

## References

- Original E203 architecture documentation
- RISC-V pipeline hazard handling techniques
- Data forwarding/bypassing in classic RISC pipelines

## Authors

Implementation by: GitHub Copilot
Based on: Hummingbird E203 RISC-V processor by Nuclei System Technology
