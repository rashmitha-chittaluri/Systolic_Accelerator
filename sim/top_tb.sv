/*`timescale 1ns / 1ps

module testbench();

localparam width_p = 8;
localparam array_width_p = 8;
localparam array_height_p = 8;
localparam num_macs_p = array_width_p * array_height_p;
localparam max_clks = 8;
logic clk_i, reset_i, en_i, error_o; 
int i;

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

logic [0:0] valid_i, valid_o;
logic [0:0] data_i;
logic [width_p-1:0] data_o, correct_data_o;

assign error_o = (data_o != correct_data_o);
 
wire [0:0] sipo_valid_w;
wire [width_p-1:0] sipo_data_w;
sipo
#(.width_p(1)
,.depth_p(width_p))
sipo_inst
(.clk_i(clk_i)
,.reset_i(reset_i)
,.valid_i(valid_i)
,.data_i(data_i)
,.valid_o(sipo_valid_w)
,.data_o(sipo_data_w)
);

// Edge detect sipo_valid_w so only one value gets read from memory.
wire [0:0] single_sipo_valid_w;
edge_detector
#(.rising_edge_p(1'b1))
sipo_valid_edge_detector_inst
(.clk_i(clk_i)
,.d_i(sipo_valid_w)
,.q_o(single_sipo_valid_w)
);

logic [0:0] fifo_ready_w, fifo_yumi_w, fifo_valid_w;
wire [width_p-1:0] matrix_data_w;

fifo
#(.width_p(width_p)
,.depth_p(num_macs_p))
fifo_inst
(.clk_i(clk_i)
,.reset_i(reset_i)
,.ready_o(fifo_ready_w)
,.valid_i(single_sipo_valid_w)
,.data_i(sipo_data_w)
,.yumi_i(fifo_yumi_w)
,.valid_o(fifo_valid_w)
,.data_o(data_o)
);

initial begin
    `ifdef VERILATOR
        $dumpfile("verilator.fst");
    `else
        $dumpfile("iverilog.vcd");
    `endif
        $dumpvars;

    $display("Begin test:");
    $display();
    #10;
    correct_data_o = '0;
    data_i = '0;
    valid_i = 1'b0;

    @(negedge reset_i);
    #5; // re-align with posedge

    #10;

    valid_i = 1'b1;
    /**/ /*data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b0;
    #10; data_i = 1'b0;
    #10; data_i = 1'b0;
    #10; data_i = 1'b1;
    #10;
    valid_i = 1'b0;
    data_i = 1'b0;
    #20;
    valid_i = 1'b1;
    /**/ /*data_i = 1'b0;
    #10; data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b1;
    #10; data_i = 1'b1;
    #10; data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b1;
    #10;
    valid_i = 1'b0;
    data_i = 1'b0;
    #20;
    valid_i = 1'b1;
    /**/ /*data_i = 1'b0;
    #10; data_i = 1'b1;
    #10; data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b1;
    #10; data_i = 1'b0;
    #10; data_i = 1'b0;
    #10; data_i = 1'b0;
    #10;
    valid_i = 1'b0;
    data_i = 1'b0;
    #20;
    fifo_yumi_w = 1'b1;
    #40;

    if (error_o) begin
        $display("Error: data_o is %b, should be %b.", data_o, correct_data_o);
        $finish();
    end
    
    if (!error_o) $finish(); // Probably didn't error.
    // Warning Verilator will reach this line and be okay, anything else will
    // probably hang.
    `ifndef VERILATOR
        $display("Error: Hang after missing call to $finish()!");
    `endif
end

final begin
      $display("Simulation time is %t", $time);
      if(error_o) begin
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
         $display("  / /_/ / /| | \\__ \\\__  ");
         $display(" / ____/ ___ |___/ /__/ / ");
         $display("/_/   /_/  |_/____/____/  ");
         $display();
         $display("Simulation Succeeded!");
      end
   end

endmodule /**/



`timescale 1ns / 1ps

module systolic_array_tb;

  // ----------------------------------------------------------------
  // Parameters (default 8×8 but easily changed)
  // ----------------------------------------------------------------
  localparam int width_p        = 8;
  localparam int array_width_p  = 8;
  localparam int array_height_p = 8;
  localparam int num_macs_p     = array_width_p * array_height_p;
  localparam int DATA_MAX       = (1 << width_p) - 1;

  // ----------------------------------------------------------------
  // Clock and Reset
  // ----------------------------------------------------------------
  logic clk_i, reset_i, en_i;
  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i; // 100 MHz clock
  end

  initial begin
    reset_i = 1;
    en_i    = 0;
    #20;
    reset_i = 0;
    en_i    = 1;
  end

  // ----------------------------------------------------------------
  // DUT Connections
  // ----------------------------------------------------------------
  logic [0:0] valid_i, yumi_i, flush_i;
  logic [0:0] valid_o, ready_o;
  logic [width_p-1:0] data_i, data_o;

  systolic_array #(
    .width_p(width_p),
    .array_width_p(array_width_p),
    .array_height_p(array_height_p)
  ) dut (
    .clk_i(clk_i),
    .reset_i(reset_i),
    .en_i(en_i),
    .flush_i(flush_i),
    .ready_o(ready_o),
    .valid_i(valid_i),
    .data_i(data_i),
    .valid_o(valid_o),
    .yumi_i(yumi_i),
    .data_o(data_o)
  );

  // ----------------------------------------------------------------
  // Matrices (A × B = C)
  // ----------------------------------------------------------------
  int A[array_height_p][array_width_p];
  int B[array_width_p][array_height_p];
  int C_expected[array_height_p][array_height_p];
  int C_received[array_height_p][array_height_p];

  // ----------------------------------------------------------------
  // Random matrix generation
  // ----------------------------------------------------------------
  task automatic gen_random_matrices();
    for (int i = 0; i < array_height_p; i++)
      for (int j = 0; j < array_width_p; j++)
        A[i][j] = $urandom_range(0, DATA_MAX);

    for (int i = 0; i < array_width_p; i++)
      for (int j = 0; j < array_height_p; j++)
        B[i][j] = $urandom_range(0, DATA_MAX);
  endtask

  // ----------------------------------------------------------------
  // Software reference model
  // ----------------------------------------------------------------
  task automatic calc_expected();
    for (int i = 0; i < array_height_p; i++)
      for (int j = 0; j < array_height_p; j++) begin
        C_expected[i][j] = 0;
        for (int k = 0; k < array_width_p; k++)
          C_expected[i][j] += A[i][k] * B[k][j];
      end
  endtask

  // ----------------------------------------------------------------
  // Feed matrices into DUT
  // ----------------------------------------------------------------
  task automatic feed_inputs();
    valid_i = 0;
    flush_i = 0;
    yumi_i  = 0;
    @(negedge reset_i);
    @(posedge clk_i);

    $display("Feeding A and B values into DUT...");
    valid_i = 1;
    for (int i = 0; i < array_height_p * array_width_p; i++) begin
      data_i = $urandom_range(0, DATA_MAX);
      @(posedge clk_i);
    end
    valid_i = 0;
  endtask

  // ----------------------------------------------------------------
  // Collect DUT outputs after flush
  // ----------------------------------------------------------------
  task automatic collect_outputs();
    flush_i = 1;
    int count = 0;
    @(posedge clk_i);
    while (count < num_macs_p) begin
      @(posedge clk_i);
      if (valid_o) begin
        C_received[count / array_width_p][count % array_width_p] = data_o;
        count++;
      end
    end
    flush_i = 0;
  endtask

  // ----------------------------------------------------------------
  // Compare and report results
  // ----------------------------------------------------------------
  task automatic check_results();
    int errors = 0;
    for (int i = 0; i < array_height_p; i++)
      for (int j = 0; j < array_height_p; j++) begin
        if (C_expected[i][j] !== C_received[i][j]) begin
          $display("Mismatch C[%0d][%0d]: expected=%0d got=%0d",
                   i, j, C_expected[i][j], C_received[i][j]);
          errors++;
        end
      end

    if (errors == 0)
      $display(" PASS: All outputs match expected results.");
    else
      $display(" FAIL: %0d mismatches found.", errors);
  endtask

  // ----------------------------------------------------------------
  // Main Test Sequence
  // ----------------------------------------------------------------
  initial begin
    @(negedge reset_i);
    repeat (3) begin // Run three random tests
      gen_random_matrices();
      calc_expected();
      feed_inputs();
      #200; // allow some compute time
      collect_outputs();
      check_results();
      #50;
    end
    $finish;
  end

  // ----------------------------------------------------------------
  // Optional waveform dump
  // ----------------------------------------------------------------
  initial begin
    $dumpfile("systolic_array_8x8.vcd");
    $dumpvars(0, systolic_array_tb);
  end

endmodule

