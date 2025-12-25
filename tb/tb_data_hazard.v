
`include "e203_defines.v"

module tb_data_hazard();

  reg  clk;
  reg  lfextclk;
  reg  rst_n;

  wire hfclk = clk;

  `define CPU_TOP u_e203_soc_top.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top
  `define EXU `CPU_TOP.u_e203_cpu.u_e203_core.u_e203_exu
  `define ITCM `CPU_TOP.u_e203_srams.u_e203_itcm_ram.u_e203_itcm_gnrl_ram.u_sirv_sim_ram

  wire [`E203_XLEN-1:0] x3 = `EXU.u_e203_exu_regfile.rf_r[3];
  wire [`E203_PC_SIZE-1:0] pc = `EXU.u_e203_exu_commit.alu_cmt_i_pc;
  wire [`E203_PC_SIZE-1:0] pc_vld = `EXU.u_e203_exu_commit.alu_cmt_i_valid;
  wire [`E203_INSTR_SIZE-1:0] instr = `EXU.i_ir;
  
  // Forwarding signals
  wire alu_wbck_valid = `EXU.u_e203_exu_disp.alu_wbck_i_valid;
  wire longp_wbck_valid = `EXU.u_e203_exu_disp.longp_wbck_i_valid;
  wire alu_fwd_rs1 = `EXU.u_e203_exu_disp.alu_fwd_rs1_match;
  wire alu_fwd_rs2 = `EXU.u_e203_exu_disp.alu_fwd_rs2_match;
  wire longp_fwd_rs1 = `EXU.u_e203_exu_disp.longp_fwd_rs1_match;
  wire longp_fwd_rs2 = `EXU.u_e203_exu_disp.longp_fwd_rs2_match;
  wire raw_dep = `EXU.u_e203_exu_disp.raw_dep;
  wire disp_valid = `EXU.u_e203_exu_disp.disp_i_valid;
  wire disp_ready = `EXU.u_e203_exu_disp.disp_i_ready;

  reg [31:0] cycle_count;
  reg [31:0] instr_count;
  reg [31:0] stall_count;
  reg [31:0] forward_count;
  
  reg [31:0] instr_start_cycle[0:100];  // Track start cycle for each instruction
  reg [31:0] instr_end_cycle[0:100];    // Track end cycle for each instruction
  reg [31:0] instr_id;
  
  reg test_started;
  reg prev_disp_valid;

  string testcase;
  integer dumpwave;

  // Cycle counter
  always @(posedge hfclk or negedge rst_n) begin 
    if(rst_n == 1'b0) begin
        cycle_count <= 32'b0;
    end
    else begin
        cycle_count <= cycle_count + 1'b1;
    end
  end

  // Instruction dispatch tracking
  always @(posedge hfclk or negedge rst_n) begin
    if(rst_n == 1'b0) begin
        instr_count <= 32'b0;
        stall_count <= 32'b0;
        forward_count <= 32'b0;
        instr_id <= 32'b0;
        test_started <= 1'b0;
        prev_disp_valid <= 1'b0;
    end
    else begin
        prev_disp_valid <= disp_valid;
        
        // Detect instruction dispatch
        if (disp_valid && disp_ready) begin
            if (!test_started && pc != 0) begin
                test_started <= 1'b1;
                $display("\n========================================");
                $display("Data Hazard Test Started at Cycle %0d", cycle_count);
                $display("========================================\n");
            end
            
            if (test_started) begin
                instr_start_cycle[instr_id] <= cycle_count;
                instr_id <= instr_id + 1;
                instr_count <= instr_count + 1;
                
                $display("[Cycle %4d] Instruction #%0d dispatched - PC=0x%08h INSTR=0x%08h", 
                         cycle_count, instr_count, pc, instr);
                
                // Report forwarding status
                if (alu_fwd_rs1 || alu_fwd_rs2) begin
                    forward_count <= forward_count + 1;
                    $display("              *** ALU Forwarding: RS1=%b RS2=%b ***", alu_fwd_rs1, alu_fwd_rs2);
                end
                if (longp_fwd_rs1 || longp_fwd_rs2) begin
                    forward_count <= forward_count + 1;
                    $display("              *** Long-pipe Forwarding: RS1=%b RS2=%b ***", longp_fwd_rs1, longp_fwd_rs2);
                end
            end
        end
        else if (disp_valid && !disp_ready && test_started) begin
            // Stall detected
            stall_count <= stall_count + 1;
            if (raw_dep) begin
                $display("[Cycle %4d] *** STALL due to RAW dependency ***", cycle_count);
            end
            else begin
                $display("[Cycle %4d] *** STALL (other reason) ***", cycle_count);
            end
        end
    end
  end

  // Test completion detection (check for success loop or timeout)
  reg test_done;
  reg [31:0] same_pc_count;
  reg [`E203_PC_SIZE-1:0] prev_pc;
  
  always @(posedge hfclk or negedge rst_n) begin
    if(rst_n == 1'b0) begin
        test_done <= 1'b0;
        same_pc_count <= 32'b0;
        prev_pc <= 0;
    end
    else if (!test_done && test_started) begin
        if (pc == prev_pc && pc != 0) begin
            same_pc_count <= same_pc_count + 1;
            if (same_pc_count > 100) begin  // Stuck at same PC for 100 cycles
                test_done <= 1'b1;
                #10
                print_summary();
                $finish;
            end
        end
        else begin
            same_pc_count <= 0;
            prev_pc <= pc;
        end
    end
  end

  task print_summary;
    begin
        $display("\n========================================");
        $display("========================================");
        $display("    Data Hazard Test Summary");
        $display("========================================");
        $display("========================================");
        $display("TESTCASE: %s", testcase);
        $display("----------------------------------------");
        $display("Total Cycles:         %0d", cycle_count);
        $display("Instructions Executed: %0d", instr_count);
        $display("Stall Cycles:         %0d", stall_count);
        $display("Forward Operations:   %0d", forward_count);
        $display("----------------------------------------");
        if (instr_count > 0) begin
            $display("CPI (Cycles Per Instruction): %0d.%02d", 
                     cycle_count / instr_count,
                     ((cycle_count % instr_count) * 100) / instr_count);
        end
        $display("Stall Rate: %0d.%02d%%", 
                 (stall_count * 100) / cycle_count,
                 ((stall_count * 100) % cycle_count * 100) / cycle_count);
        $display("========================================");
        $display("\nTest completed successfully!\n");
    end
  endtask

  initial begin
    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");  
    if($value$plusargs("TESTCASE=%s",testcase))begin
      $display("TESTCASE=%s",testcase);
    end

    clk   <=0;
    lfextclk   <=0;
    rst_n <=0;
    #120 rst_n <=1;

    // Wait for test completion (max 50000 cycles)
    #200000;
    
    if (!test_done) begin
        $display("\n*** Test timed out after 50000 cycles ***\n");
        print_summary();
    end
    
    $finish;
  end

  initial begin
    #10000000  // 10ms timeout
    $display("\n!!! SIMULATION TIMEOUT !!!\n");
    $finish;
  end

  always begin 
     #2 clk <= ~clk;
  end

  always begin 
     #33 lfextclk <= ~lfextclk;
  end

  initial begin
    if($value$plusargs("DUMPWAVE=%d",dumpwave)) begin
      if(dumpwave != 0) begin
	 `ifdef iverilog
            $display("iverilog used");
	    $dumpfile("tb_data_hazard.vcd");
            $dumpvars(0, tb_data_hazard);
         `endif
      end
    end
  end

  integer i;
  reg [7:0] itcm_mem [0:(`E203_ITCM_RAM_DP*8)-1];
  
  initial begin
    $readmemh({testcase, ".verilog"}, itcm_mem);

    for (i=0;i<(`E203_ITCM_RAM_DP);i=i+1) begin
        `ITCM.mem_r[i][00+7:00] = itcm_mem[i*8+0];
        `ITCM.mem_r[i][08+7:08] = itcm_mem[i*8+1];
        `ITCM.mem_r[i][16+7:16] = itcm_mem[i*8+2];
        `ITCM.mem_r[i][24+7:24] = itcm_mem[i*8+3];
        `ITCM.mem_r[i][32+7:32] = itcm_mem[i*8+4];
        `ITCM.mem_r[i][40+7:40] = itcm_mem[i*8+5];
        `ITCM.mem_r[i][48+7:48] = itcm_mem[i*8+6];
        `ITCM.mem_r[i][56+7:56] = itcm_mem[i*8+7];
    end
    
    $display("Program loaded from %s.verilog", testcase);
  end

  e203_soc_top u_e203_soc_top (
    .hfextclk(hfclk),
    .hfxoscen(),
    .lfextclk(lfextclk),
    .lfxoscen(),
    .io_pads_jtag_TCK_i_ival(1'b0),
    .io_pads_jtag_TMS_i_ival(1'b0),
    .io_pads_jtag_TDI_i_ival(1'b0),
    .io_pads_jtag_TDO_o_oval(),
    .io_pads_jtag_TDO_o_oe(),
    .io_pads_gpio_0_i_ival(1'b0),
    .io_pads_gpio_0_o_oval(),
    .io_pads_gpio_0_o_oe(),
    .io_pads_gpio_1_i_ival(1'b0),
    .io_pads_gpio_1_o_oval(),
    .io_pads_gpio_1_o_oe(),
    .io_pads_gpio_2_i_ival(1'b0),
    .io_pads_gpio_2_o_oval(),
    .io_pads_gpio_2_o_oe(),
    .io_pads_gpio_3_i_ival(1'b0),
    .io_pads_gpio_3_o_oval(),
    .io_pads_gpio_3_o_oe(),
    .io_pads_gpio_4_i_ival(1'b0),
    .io_pads_gpio_4_o_oval(),
    .io_pads_gpio_4_o_oe(),
    .io_pads_gpio_5_i_ival(1'b0),
    .io_pads_gpio_5_o_oval(),
    .io_pads_gpio_5_o_oe(),
    .io_pads_gpio_6_i_ival(1'b0),
    .io_pads_gpio_6_o_oval(),
    .io_pads_gpio_6_o_oe(),
    .io_pads_gpio_7_i_ival(1'b0),
    .io_pads_gpio_7_o_oval(),
    .io_pads_gpio_7_o_oe(),
    .io_pads_gpio_8_i_ival(1'b0),
    .io_pads_gpio_8_o_oval(),
    .io_pads_gpio_8_o_oe(),
    .io_pads_gpio_9_i_ival(1'b0),
    .io_pads_gpio_9_o_oval(),
    .io_pads_gpio_9_o_oe(),
    .io_pads_gpio_10_i_ival(1'b0),
    .io_pads_gpio_10_o_oval(),
    .io_pads_gpio_10_o_oe(),
    .io_pads_gpio_11_i_ival(1'b0),
    .io_pads_gpio_11_o_oval(),
    .io_pads_gpio_11_o_oe(),
    .io_pads_gpio_12_i_ival(1'b0),
    .io_pads_gpio_12_o_oval(),
    .io_pads_gpio_12_o_oe(),
    .io_pads_gpio_13_i_ival(1'b0),
    .io_pads_gpio_13_o_oval(),
    .io_pads_gpio_13_o_oe(),
    .io_pads_gpio_14_i_ival(1'b0),
    .io_pads_gpio_14_o_oval(),
    .io_pads_gpio_14_o_oe(),
    .io_pads_gpio_15_i_ival(1'b0),
    .io_pads_gpio_15_o_oval(),
    .io_pads_gpio_15_o_oe(),
    .io_pads_gpio_16_i_ival(1'b0),
    .io_pads_gpio_16_o_oval(),
    .io_pads_gpio_16_o_oe(),
    .io_pads_gpio_17_i_ival(1'b0),
    .io_pads_gpio_17_o_oval(),
    .io_pads_gpio_17_o_oe(),
    .io_pads_gpio_18_i_ival(1'b0),
    .io_pads_gpio_18_o_oval(),
    .io_pads_gpio_18_o_oe(),
    .io_pads_gpio_19_i_ival(1'b0),
    .io_pads_gpio_19_o_oval(),
    .io_pads_gpio_19_o_oe(),
    .io_pads_gpio_20_i_ival(1'b0),
    .io_pads_gpio_20_o_oval(),
    .io_pads_gpio_20_o_oe(),
    .io_pads_gpio_21_i_ival(1'b0),
    .io_pads_gpio_21_o_oval(),
    .io_pads_gpio_21_o_oe(),
    .io_pads_gpio_22_i_ival(1'b0),
    .io_pads_gpio_22_o_oval(),
    .io_pads_gpio_22_o_oe(),
    .io_pads_gpio_23_i_ival(1'b0),
    .io_pads_gpio_23_o_oval(),
    .io_pads_gpio_23_o_oe(),
    .io_pads_gpio_24_i_ival(1'b0),
    .io_pads_gpio_24_o_oval(),
    .io_pads_gpio_24_o_oe(),
    .io_pads_gpio_25_i_ival(1'b0),
    .io_pads_gpio_25_o_oval(),
    .io_pads_gpio_25_o_oe(),
    .io_pads_gpio_26_i_ival(1'b0),
    .io_pads_gpio_26_o_oval(),
    .io_pads_gpio_26_o_oe(),
    .io_pads_gpio_27_i_ival(1'b0),
    .io_pads_gpio_27_o_oval(),
    .io_pads_gpio_27_o_oe(),
    .io_pads_gpio_28_i_ival(1'b0),
    .io_pads_gpio_28_o_oval(),
    .io_pads_gpio_28_o_oe(),
    .io_pads_gpio_29_i_ival(1'b0),
    .io_pads_gpio_29_o_oval(),
    .io_pads_gpio_29_o_oe(),
    .io_pads_gpio_30_i_ival(1'b0),
    .io_pads_gpio_30_o_oval(),
    .io_pads_gpio_30_o_oe(),
    .io_pads_gpio_31_i_ival(1'b0),
    .io_pads_gpio_31_o_oval(),
    .io_pads_gpio_31_o_oe(),
    .io_pads_qspi_sck_o_oval(),
    .io_pads_qspi_dq_0_i_ival(1'b0),
    .io_pads_qspi_dq_0_o_oval(),
    .io_pads_qspi_dq_0_o_oe(),
    .io_pads_qspi_dq_1_i_ival(1'b0),
    .io_pads_qspi_dq_1_o_oval(),
    .io_pads_qspi_dq_1_o_oe(),
    .io_pads_qspi_dq_2_i_ival(1'b0),
    .io_pads_qspi_dq_2_o_oval(),
    .io_pads_qspi_dq_2_o_oe(),
    .io_pads_qspi_dq_3_i_ival(1'b0),
    .io_pads_qspi_dq_3_o_oval(),
    .io_pads_qspi_dq_3_o_oe(),
    .io_pads_qspi_cs_0_o_oval(),
    .io_pads_aon_erst_n_i_ival(rst_n),
    .io_pads_aon_pmu_dwakeup_n_i_ival(1'b1),
    .io_pads_aon_pmu_vddpaden_o_oval(),
    .io_pads_aon_pmu_padrst_o_oval(),
    .io_pads_bootrom_n_i_ival(1'b0),
    .io_pads_dbgmode0_n_i_ival(1'b1),
    .io_pads_dbgmode1_n_i_ival(1'b1),
    .io_pads_dbgmode2_n_i_ival(1'b1) 
  );

endmodule
