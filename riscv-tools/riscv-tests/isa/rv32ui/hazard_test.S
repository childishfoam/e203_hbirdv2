# See LICENSE for license details.

#*****************************************************************************
# hazard_test.S
#-----------------------------------------------------------------------------
#
# Test data hazard handling with forwarding
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # Test program with 20 instructions showing data hazards
  # These instructions will be monitored by the testbench
  
  # Instruction 1: addi x1, x0, 5
  addi x1, x0, 5
  
  # Instruction 2: addi x2, x0, 3
  addi x2, x0, 3
  
  # Instruction 3: add x3, x1, x2    # RAW hazard on x1, x2
  add x3, x1, x2
  
  # Instruction 4: sw x3, 0(x0)      # RAW hazard on x3
  sw x3, 0(x0)
  
  # Instruction 5: lw x4, 0(x0)      # Load instruction (long-pipe)
  lw x4, 0(x0)
  
  # Instruction 6: add x5, x4, x1    # RAW hazard on x4 (load-use hazard)
  add x5, x4, x1
  
  # Instruction 7: sub x6, x5, x2    # RAW hazard on x5
  sub x6, x5, x2
  
  # Instruction 8: mul x7, x6, x3    # RAW hazard on x6
  mul x7, x6, x3
  
  # Instruction 9: addi x1, x0, 8    # WAW hazard on x1
  addi x1, x0, 8
  
  # Instruction 10: add x8, x7, x1   # RAW hazard on x7, x1
  add x8, x7, x1
  
  # Instruction 11: and x9, x8, x5   # RAW hazard on x8
  and x9, x8, x5
  
  # Instruction 12: or x10, x9, x7   # RAW hazard on x9
  or x10, x9, x7
  
  # Instruction 13: xor x11, x10, x8 # RAW hazard on x10
  xor x11, x10, x8
  
  # Instruction 14: sll x12, x11, x2 # RAW hazard on x11
  sll x12, x11, x2
  
  # Instruction 15: srl x13, x12, x1 # RAW hazard on x12
  srl x13, x12, x1
  
  # Instruction 16: addi x14, x13, -1 # RAW hazard on x13
  addi x14, x13, -1
  
  # Instruction 17: sw x14, 4(x0)    # RAW hazard on x14
  sw x14, 4(x0)
  
  # Instruction 18: lw x15, 4(x0)    # Load instruction (long-pipe)
  lw x15, 4(x0)
  
  # Instruction 19: add x16, x15, x10 # RAW hazard on x15 (load-use hazard)
  add x16, x15, x10
  
  # Instruction 20: mul x17, x16, x13 # RAW hazard on x16
  mul x17, x16, x13
  
  # Store final result to verify correctness
  sw x17, 8(x0)
  
  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
