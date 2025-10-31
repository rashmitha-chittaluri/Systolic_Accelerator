`timescale 1ns / 1ps

module testbench();

  // ======================================================
  // PARAMETERS (8x8 matrix configuration)
  // ======================================================
  localparam width_p        = 8;
  localparam array_width_p  = 8;
  localparam array_height_p = 8;
  localparam max_clks       = 2 * array_width_p * array_height_p;

  logic clk_i, reset_i, en_i, error_o;
  int i;
  logic [31:0] correct_z_w;

  // ======================================================
  // CLOCK AND RESET GENERATION
  // ======================================================
  nonsynth_clock_gen
   #(.cycle_time_p(10))
   cg
   (.clk_o(clk_i));

  nonsynth_reset_gen
   #(.num_clocks_p(1)
    ,.reset_cycles_lo_p(1)
    ,.reset_cycles_hi_p(10))
   rg
   (.clk_i(clk_i)
   ,.async_reset_o(reset_i));

  // ======================================================
  // SIGNALS
  // ======================================================
  logic [width_p-1:0] data_i, data_o, correct_data_o;
  logic [0:0] flush_i, ready_o, valid_i, valid_o, yumi_i;

  assign en_i    = 1'b1;
  assign error_o = (data_o != correct_data_o);

  // ======================================================
  // DEBUG WIRES
  // ======================================================
  wire [0:0] throwaway_busy_w, throwaway_idle_w;
  wire [7:0] throwaway_onehot_w;

  // ======================================================
  // DUT INSTANTIATION
  // ======================================================
  systolic_array
  #(.width_p(width_p)
   ,.array_width_p(array_width_p)
   ,.array_height_p(array_height_p)
   )
  dut
  (.clk_i(clk_i)
  ,.reset_i(reset_i)
  ,.en_i(en_i)
  ,.flush_i(flush_i)
  ,.ready_o(ready_o)
  ,.valid_i(valid_i)
  ,.data_i(data_i)
  ,.valid_o(valid_o)
  ,.yumi_i(yumi_i)
  ,.data_o(data_o)
  ,.busy_o(throwaway_busy_w)
  ,.idle_o(throwaway_idle_w)
  ,.onehot_o(throwaway_onehot_w)
  );

  // ======================================================
  // TEST SEQUENCE
  // ======================================================
  initial begin
    `ifdef VERILATOR
      $dumpfile("verilator.fst");
    `else
      $dumpfile("iverilog.vcd");
    `endif
      $dumpvars;

    $display("=====================================");
    $display("         BEGIN 8x8 TESTBENCH");
    $display("=====================================");

    #10;
    correct_data_o = '0;
    data_i = '0;
    flush_i = 1'b0;
    valid_i = 1'b0;
    yumi_i  = 1'b0;

    @(negedge reset_i);
    #5; // re-align with posedge

    // ======================================================
    // INPUT SEQUENCE FOR 8x8 MATRIX (TOTAL 64 INPUTS)
    // ======================================================
    repeat (64) begin
      valid_i = 1'b1;
      data_i  = $urandom_range(1, 10)[7:0];  // random 8-bit inputs
      #10;
      valid_i = 1'b0;
      #10;
    end

    @(posedge ready_o);
    #100;

    // Trigger flush to output data
    flush_i = 1'b1;
    #10;
    flush_i = 1'b0;

    // Wait for all outputs to drain
    #200;

    if (error_o) begin
      $display("Error detected!");
      $finish();
    end

    if (!error_o) $finish();
    `ifndef VERILATOR
      $display("Error: Hang after missing call to $finish()!");
    `endif
  end

  // ======================================================
  // FINAL SIMULATION STATUS DISPLAY
  // ======================================================
  final begin
    $display("Simulation time is %t", $time);
    if (error_o) begin
      $display("    ______                    ");
      $display("   / ____/_____________  _____");
      $display("  / __/ / ___/ ___/ __ \\/ ___/");
      $display(" / /___/ /  / /  / /_/ / /    ");
      $display("/_____/_/  /_/   \\____/_/     ");
      $display();
      $display("Simulation Failed");
    end else begin
      $display("    ____  ___   __________");
      $display("   / __ \\/   | / ___/ ___/");
      $display("  / /_/ / /| | \\__ \\__  ");
      $display(" / ____/ ___ |___/ /__/ / ");
      $display("/_/   /_/  |_/____/____/  ");
      $display();
      $display("Simulation Succeeded!");
    end
  end

  // ======================================================
  // THROUGHPUT MEASUREMENT BLOCK
  // ======================================================
  real CLK_PERIOD_NS = 10.0;       // 100 MHz clock
  integer cycle_count = 0;         // total simulation cycles
  integer input_count = 0;         // total valid inputs given
  integer output_count = 0;        // total valid outputs received
  time start_time, end_time;       // timestamps
  real throughput_ops_per_cycle;
  real throughput_ops_per_sec;

  // Count total cycles
  always @(posedge clk_i) begin
    if (reset_i)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  // Count input and output valid pulses
  always @(posedge clk_i) begin
    if (!reset_i && valid_i)
      input_count <= input_count + 1;
    if (!reset_i && valid_o)
      output_count <= output_count + 1;
  end

  // Capture start and stop time
  initial begin
    @(negedge reset_i);
    start_time = $time;
  end

  // Print throughput report automatically when simulation ends
  final begin
    end_time = $time;
    throughput_ops_per_cycle = (output_count * 1.0) / (cycle_count * 1.0);
    throughput_ops_per_sec   = (output_count * 1.0) / ((end_time - start_time) * 1e-9);

    $display("\n=====================================");
    $display("          THROUGHPUT REPORT");
    $display("=====================================");
    $display(" Clock Period (ns):       %.2f", CLK_PERIOD_NS);
    $display(" Total Cycles:            %0d", cycle_count);
    $display(" Valid Inputs:            %0d", input_count);
    $display(" Valid Outputs:           %0d", output_count);
    $display(" Simulation Time (ns):    %.2f", ($realtime - start_time));
    $display(" Throughput (ops/cycle):  %.4f", throughput_ops_per_cycle);
    $display(" Throughput (Mops/sec):   %.2f", throughput_ops_per_sec / 1e6);
    $display("=====================================\n");
  end

endmodule
