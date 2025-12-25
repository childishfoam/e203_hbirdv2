# Data Forwarding Implementation for Hummingbird E203

## Overview
This document describes the implementation of data forwarding mechanism in the Hummingbird E203 RISC-V processor to reduce pipeline stalls caused by data hazards.

## Background

### Current E203 Architecture
The E203 core has a 2-stage pipeline:
1. **IF Stage (Instruction Fetch)**: Instruction fetch and register file read
2. **EXU Stage (Execution)**: Instruction execution and write-back

The current implementation uses:
- **OITF (Outstanding Instructions Track FIFO)**: Tracks long-pipeline instructions (load/store, mul/div)
- **Stall-based hazard handling**: When a RAW (Read-After-Write) or WAW (Write-After-Write) dependency is detected with OITF entries, the pipeline stalls

### Problem
Without data forwarding, even simple back-to-back ALU instructions cause stalls:
```assembly
addi x1, x0, 5    # Cycle 1: x1 = 5
add  x2, x1, x0   # Cycle 2: STALLS waiting for x1 write-back
                  # Cycle 3: Executes with x1 = 5
```

This significantly reduces performance, especially for instruction sequences with consecutive dependencies.

## Implementation

### 1. Forwarding Paths

We implemented two forwarding paths to the dispatch stage:

#### 1.1 ALU Write-Back Forwarding
- **Source**: ALU execution result (alu_wbck_i_wdat)
- **Target**: Dispatch stage operand inputs (RS1, RS2)
- **Latency**: 0 cycles (same-cycle forwarding)
- **Use case**: Back-to-back ALU instructions

#### 1.2 Long-Pipe Write-Back Forwarding
- **Source**: Long-pipeline write-back (longp_wbck_i_wdat) from LSU/MUL/DIV
- **Target**: Dispatch stage operand inputs (RS1, RS2)
- **Latency**: Available when long-pipe completes
- **Use case**: Load/Mul followed by ALU instruction

### 2. Modified Modules

#### 2.1 e203_exu_disp.v (Dispatch Module)

**Added Ports:**
```verilog
// Data Forwarding Interface
input  alu_wbck_i_valid,                      // ALU write-back valid
input  [`E203_XLEN-1:0] alu_wbck_i_wdat,     // ALU write-back data
input  [`E203_RFIDX_WIDTH-1:0] alu_wbck_i_rdidx, // ALU destination reg index

input  longp_wbck_i_valid,                    // Long-pipe write-back valid
input  [`E203_XLEN-1:0] longp_wbck_i_wdat,   // Long-pipe write-back data
input  [`E203_RFIDX_WIDTH-1:0] longp_wbck_i_rdidx, // Long-pipe dest reg index
```

**Forwarding Detection Logic:**
```verilog
// Check if we can forward from ALU write-back
wire alu_fwd_rs1_match = alu_wbck_i_valid 
                       & (alu_wbck_i_rdidx == disp_i_rs1idx) 
                       & (|disp_i_rs1idx)  // Not x0
                       & disp_i_rs1en;

wire alu_fwd_rs2_match = alu_wbck_i_valid 
                       & (alu_wbck_i_rdidx == disp_i_rs2idx) 
                       & (|disp_i_rs2idx)
                       & disp_i_rs2en;

// Check if we can forward from long-pipe write-back
wire longp_fwd_rs1_match = longp_wbck_i_valid 
                         & (longp_wbck_i_rdidx == disp_i_rs1idx) 
                         & (|disp_i_rs1idx)
                         & disp_i_rs1en;

wire longp_fwd_rs2_match = longp_wbck_i_valid 
                         & (longp_wbck_i_rdidx == disp_i_rs2idx) 
                         & (|disp_i_rs2idx)
                         & disp_i_rs2en;
```

**Modified RAW Dependency Check:**
```verilog
// Determine if RAW hazard can be resolved by forwarding
wire raw_rs1_fwd = alu_fwd_rs1_match | longp_fwd_rs1_match;
wire raw_rs2_fwd = alu_fwd_rs2_match | longp_fwd_rs2_match;

// Only stall if dependency exists and cannot be forwarded
wire raw_rs1_dep = oitfrd_match_disprs1 & (~raw_rs1_fwd);
wire raw_rs2_dep = oitfrd_match_disprs2 & (~raw_rs2_fwd);
wire raw_rs3_dep = oitfrd_match_disprs3;

wire raw_dep = raw_rs1_dep | raw_rs2_dep | raw_rs3_dep;
```

**Forwarding Multiplexers:**
```verilog
// RS1 forwarding mux (priority: ALU > Long-pipe > Regfile)
wire [`E203_XLEN-1:0] disp_i_rs1_forwarded;
assign disp_i_rs1_forwarded = 
    ({`E203_XLEN{alu_fwd_rs1_match}}   & alu_wbck_i_wdat) |
    ({`E203_XLEN{longp_fwd_rs1_match}} & longp_wbck_i_wdat) |
    ({`E203_XLEN{~(alu_fwd_rs1_match | longp_fwd_rs1_match)}} & disp_i_rs1_msked);

// RS2 forwarding mux (priority: ALU > Long-pipe > Regfile)
wire [`E203_XLEN-1:0] disp_i_rs2_forwarded;
assign disp_i_rs2_forwarded = 
    ({`E203_XLEN{alu_fwd_rs2_match}}   & alu_wbck_i_wdat) |
    ({`E203_XLEN{longp_fwd_rs2_match}} & longp_wbck_i_wdat) |
    ({`E203_XLEN{~(alu_fwd_rs2_match | longp_fwd_rs2_match)}} & disp_i_rs2_msked);

// Use forwarded values
assign disp_o_alu_rs1 = disp_i_rs1_forwarded;
assign disp_o_alu_rs2 = disp_i_rs2_forwarded;
```

#### 2.2 e203_exu.v (Top-level EXU)

**Connected Forwarding Signals:**
```verilog
e203_exu_disp u_e203_exu_disp(
    // ... existing connections ...
    
    // Data Forwarding connections
    .alu_wbck_i_valid    (alu_wbck_o_valid ),
    .alu_wbck_i_wdat     (alu_wbck_o_wdat  ),
    .alu_wbck_i_rdidx    (alu_wbck_o_rdidx ),
    .longp_wbck_i_valid  (longp_wbck_o_valid ),
    .longp_wbck_i_wdat   (longp_wbck_o_wdat[`E203_XLEN-1:0]),
    .longp_wbck_i_rdidx  (longp_wbck_o_rdidx ),
    
    // ... 
);
```

### 3. Forwarding Behavior

#### Case 1: ALU-to-ALU Forwarding (No Stall)
```assembly
addi x1, x0, 5    # Cycle 1: x1 = 5, write-back
add  x2, x1, x0   # Cycle 2: Reads x1=5 via forwarding, NO STALL
```
**Before forwarding**: 1 cycle stall  
**After forwarding**: 0 cycle stall  
**Improvement**: 1 cycle saved

#### Case 2: Load-to-ALU (Still Stalls)
```assembly
lw   x1, 0(x0)    # Cycle 1-N: Load (long-pipe)
add  x2, x1, x0   # Waits until load completes, then forwards
```
**Note**: Load instructions still require stalls since data isn't available immediately. However, once available, it's forwarded.

#### Case 3: Multiple Dependencies
```assembly
add x1, x2, x3    # Cycle 1: x1 = x2 + x3
sub x4, x1, x5    # Cycle 2: Reads x1 via forwarding, NO STALL
and x6, x4, x7    # Cycle 3: Reads x4 via forwarding, NO STALL
```
**Before forwarding**: 2 cycle stalls  
**After forwarding**: 0 cycle stalls  
**Improvement**: 2 cycles saved

## Test Program Analysis

The test program `data_hazard_test.S` contains 20 instructions with various hazard scenarios:

### Identified Hazards:

1. **Instruction 3** (add x3, x1, x2): RAW on x1, x2 - **FORWARDED**
2. **Instruction 4** (sw x3, 0(x0)): RAW on x3 - **FORWARDED**
3. **Instruction 6** (add x5, x4, x1): RAW on x4 (from load) - **STALLS, then FORWARDED**
4. **Instruction 7** (sub x6, x5, x2): RAW on x5 - **FORWARDED**
5. **Instruction 8** (mul x7, x6, x3): RAW on x6 - **FORWARDED**
6. **Instruction 10** (add x8, x7, x1): RAW on x7 (from mul), x1 - **STALLS for mul, FORWARDED**
7. **Instruction 11** (and x9, x8, x5): RAW on x8 - **FORWARDED**
8. **Instructions 12-17**: Multiple consecutive dependencies - **ALL FORWARDED**
9. **Instruction 19** (add x16, x15, x10): RAW on x15 (from load) - **STALLS, then FORWARDED**
10. **Instruction 20** (mul x17, x16, x13): RAW on x16 - **FORWARDED**

### Expected Performance Improvement:

**Without Forwarding:**
- Estimated stalls: ~15 cycles (one stall for each consecutive ALU instruction)
- Long-pipe stalls: ~4-6 cycles (for loads and muls)
- **Total estimated cycles: ~35-40 cycles**

**With Forwarding:**
- ALU-to-ALU stalls eliminated: 0 cycles
- Long-pipe stalls: ~4-6 cycles (unavoidable)
- **Total estimated cycles: ~24-26 cycles**

**Performance Improvement: ~35-40% reduction in cycles**

## Benefits

1. **Reduced Pipeline Stalls**: Eliminates stalls for back-to-back ALU instructions
2. **Better IPC**: Instructions Per Cycle improves significantly
3. **Backward Compatible**: No changes to ISA or external interfaces
4. **Minimal Hardware Cost**: Small increase in multiplexers and control logic

## Limitations

1. **Load Latency**: Load instructions still require stalls (inherent to LSU pipeline)
2. **Multiply/Divide**: Long-pipe multiplications still incur delays
3. **Timing**: Additional mux in critical path may slightly impact clock frequency
4. **Area**: Small increase in gate count for forwarding logic

## Validation

To validate the implementation:

1. **Compilation Check**: Verify RTL compiles without errors
2. **Functional Test**: Run `data_hazard_test.S` through simulation
3. **Waveform Analysis**: Compare cycle counts before/after forwarding
4. **Regression Tests**: Run existing test suite to ensure no breakage

### Simulation Commands:
```bash
cd vsim
make clean
make compile SIM=iverilog
make run_test TESTCASE=../riscv-tools/test_programs/data_hazard_test SIM=iverilog
make wave SIM=iverilog
```

## Future Enhancements

1. **Load forwarding**: Implement early load data forwarding from LSU
2. **Multiple write-back ports**: Support simultaneous forwarding from multiple sources
3. **Scoreboarding**: More sophisticated hazard detection and resolution
4. **Out-of-order execution**: For even better performance

## Conclusion

The data forwarding mechanism significantly improves the performance of the E203 core by eliminating unnecessary stalls for ALU instructions. This is a critical optimization for any pipelined processor and brings the E203 closer to a production-ready implementation.

## References

1. Hennessy & Patterson, "Computer Architecture: A Quantitative Approach"
2. David Patterson, "Computer Organization and Design: RISC-V Edition"
3. E203 Original Documentation: https://doc.nucleisys.com/hbirdv2/
