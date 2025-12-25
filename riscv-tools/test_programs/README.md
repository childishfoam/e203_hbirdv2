# Data Hazard Test Program

## 文件说明 (File Description)

- `data_hazard_test.S` - 汇编测试程序，包含各种RAW数据冒险场景
- `Makefile` - 编译脚本
- `README.md` - 本文件

## 编译测试程序 (Compile Test Program)

测试程序需要编译成Verilog格式才能被仿真器加载。

The test program needs to be compiled into Verilog format to be loaded by the simulator.

### 前置要求 (Prerequisites)

需要安装 RISC-V 工具链：
- `riscv-nuclei-elf-gcc` 或 `riscv32-unknown-elf-gcc`
- `riscv-nuclei-elf-objdump` 或 `riscv32-unknown-elf-objdump`
- `riscv-nuclei-elf-objcopy` 或 `riscv32-unknown-elf-objcopy`

如果使用不同的工具链前缀，请修改 Makefile 中的 `RISCV_PREFIX` 变量。

### 编译命令 (Compile Commands)

```bash
cd riscv-tools/test_programs
make
```

这将生成：
- `data_hazard_test` - ELF 可执行文件
- `data_hazard_test.dump` - 反汇编文件（可读的汇编代码）
- `data_hazard_test.verilog` - Verilog 十六进制格式（用于仿真）

This will generate:
- `data_hazard_test` - ELF executable
- `data_hazard_test.dump` - Disassembly file (readable assembly code)
- `data_hazard_test.verilog` - Verilog hex format (for simulation)

## 运行仿真 (Run Simulation)

### 使用专用测试台 (Using Dedicated Testbench)

专用测试台 `tb_data_hazard.v` 提供详细的周期和指令追踪信息。

The dedicated testbench `tb_data_hazard.v` provides detailed cycle and instruction tracking.

```bash
cd vsim
make clean
make compile SIM=iverilog
make run_test TESTCASE=../riscv-tools/test_programs/data_hazard_test SIM=iverilog
```

### 查看波形 (View Waveform)

```bash
make wave SIM=iverilog
```

这将打开 GTKWave 查看波形文件 `tb_data_hazard.vcd`

## 输出信息 (Output Information)

测试台将打印以下信息：

The testbench will print:

1. **每条指令的执行周期** - Execution cycle for each instruction
   ```
   [Cycle XXXX] Instruction #X dispatched - PC=0xXXXXXXXX INSTR=0xXXXXXXXX
   ```

2. **前推检测** - Forwarding detection
   ```
   *** ALU Forwarding: RS1=1 RS2=0 ***
   *** Long-pipe Forwarding: RS1=1 RS2=0 ***
   ```

3. **停顿检测** - Stall detection
   ```
   *** STALL due to RAW dependency ***
   ```

4. **最终统计** - Final statistics
   ```
   Total Cycles:          XXX
   Instructions Executed: XXX
   Stall Cycles:          XXX
   Forward Operations:    XXX
   CPI (Cycles Per Instruction): X.XX
   Stall Rate: XX.XX%
   ```

## 测试程序说明 (Test Program Description)

测试程序包含以下数据冒险场景：

The test program contains the following data hazard scenarios:

1. **ALU-to-ALU 前推** - 连续ALU指令之间的依赖（应该被前推）
2. **Load-to-ALU 依赖** - Load指令后立即使用结果（需要停顿）
3. **前推链** - 多条连续指令的依赖链
4. **寄存器复用** - 同一个寄存器被多次写入
5. **复杂依赖** - 多个源寄存器的依赖

## 性能对比 (Performance Comparison)

### 无前推机制 (Without Forwarding)
- 预期周期数：~35-40 cycles
- 停顿周期：~15 cycles (ALU) + 4-6 cycles (Load/Mul)

### 有前推机制 (With Forwarding)
- 预期周期数：~24-26 cycles
- 停顿周期：~4-6 cycles (仅Load/Mul)
- **性能提升：约35-40%**

## 故障排除 (Troubleshooting)

### 错误：找不到 .verilog 文件
```
ERROR: $readmemh: Unable to open ../riscv-tools/test_programs/data_hazard_test.verilog
```
**解决方法**：首先编译测试程序（参见上面的编译命令）

### 错误：工具链未安装
```
riscv-nuclei-elf-gcc: command not found
```
**解决方法**：
1. 安装 RISC-V 工具链
2. 或修改 Makefile 中的 `RISCV_PREFIX` 为你的工具链前缀

### 仿真一直运行卷积测试
**原因**：默认的 tb_top.v 可能被其他测试配置
**解决方法**：使用专用的 tb_data_hazard.v 测试台（参见上面的运行命令）

## 关键信号 (Key Signals)

在 GTKWave 中查看以下信号以分析前推行为：

View these signals in GTKWave to analyze forwarding behavior:

- `disp_i_valid` / `disp_i_ready` - 指令分派握手信号
- `alu_fwd_rs1_match` / `alu_fwd_rs2_match` - ALU前推匹配信号
- `longp_fwd_rs1_match` / `longp_fwd_rs2_match` - 长流水线前推匹配信号
- `raw_dep` - RAW依赖检测信号
- `disp_i_rs1_forwarded` / `disp_i_rs2_forwarded` - 前推后的操作数

## 更多信息 (More Information)

详细的实现说明请参见：
- `doc/data_forwarding_implementation.md` - 实现详细文档
- `doc/SUMMARY_CN.md` - 中文总结
- `doc/EXPERIMENT_README.md` - 实验指南
