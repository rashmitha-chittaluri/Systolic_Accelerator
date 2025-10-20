`timescale 1ns / 1ps

module systolic_array_tb;

  // ================================================================
  // Parameters
  // ================================================================
  localparam int width_p        = 8;
  localparam int array_width_p  = 8;
  localparam int array_height_p = 8;
  localparam int num_macs_p     = array_width_p * array_height_p;
  localparam int MAX_VAL        = (1 << width_p) - 1;

  // ================================================================
  // Clock and Reset
  // ================================================================
  logic clk_i, reset_i, en_i;
  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i; // 100 MHz
  end

  initial begin
    reset_i = 1;
    en_i    = 0;
    #25;
    reset_i = 0;
    en_i    = 1;
  end

  // ================================================================
  // DUT Interface
  // ================================================================
  logic valid_i, yumi_i, flush_i;
  logic ready_o, valid_o;
  logic [width_p-1:0] data_i, data_o;

  // Extra DUT outputs
  logic busy_o, idle_o;
  logic [7:0] onehot_o;

  // ================================================================
  // DUT Instantiation
  // ================================================================
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
    .data_o(data_o),
    .busy_o(busy_o),
    .idle_o(idle_o),
    .onehot_o(onehot_o)
  );

  // ================================================================
  // Simple random input generator (Verilator friendly)
  // ================================================================
  typedef struct {
    bit [width_p-1:0] value;
    bit valid;
  } input_packet_t;

  input_packet_t packet;

  // ================================================================
  // Measurement and Reference Data
  // ================================================================
  int total_cycles;
  int output_count;
  int errors;
  int min_size;
  realtime start_time, end_time;
  real throughput;
  real min_throughput = 0.50;
  int golden_output[$];
  int received_output[$];

  // ================================================================
  // Stimulus and Measurement
  // ================================================================
  initial begin
    @(negedge reset_i);
    valid_i = 0;
    flush_i = 0;
    yumi_i  = 0;
    data_i  = 0;
    total_cycles = 0;
    output_count = 0;
    errors = 0;
    golden_output.delete();
    received_output.delete();

    start_time = $realtime;

    // Main traffic generator
    repeat (500) begin
      // Manual constrained randomization (Verilator compatible)
      packet.value = $urandom_range(0, MAX_VAL);
      packet.valid = ($urandom_range(0, 9) < 8); // 80% chance valid=1

      valid_i = packet.valid;
      data_i  = packet.value;

      // Build simple golden sequence
      if (valid_i)
        golden_output.push_back(data_i);

      // Output handshake
      yumi_i = valid_o;

      @(posedge clk_i);
      total_cycles++;

      if (valid_o && yumi_i) begin
        received_output.push_back(data_o);
        output_count++;
      end
    end

    end_time = $realtime;

    // Small flush window
    flush_i = 1;
    repeat (5) @(posedge clk_i);
    flush_i = 0;

    // ============================================================
    // Throughput Calculation
    // ============================================================
    throughput = (output_count * 1.0) / total_cycles;
    $display("----------------------------------------------------------");
    $display("Total cycles        : %0d", total_cycles);
    $display("Total outputs       : %0d", output_count);
    $display("Throughput (out/clk): %0.3f", throughput);
    $display("----------------------------------------------------------");

    // ============================================================
    // Functional Check (simple 1-to-1 compare)
    // ============================================================
    if (golden_output.size() < received_output.size())
      min_size = golden_output.size();
    else
      min_size = received_output.size();

    for (int i = 0; i < min_size; i++) begin
      if (received_output[i] !== golden_output[i]) begin
        $display("Mismatch at [%0d]: expected=%0d got=%0d",
                  i, golden_output[i], received_output[i]);
        errors++;
      end
    end

    // ============================================================
    // Pass / Fail Decision
    // ============================================================
    if ((errors == 0) && (throughput >= min_throughput))
      $display("PASS: No mismatches and throughput %.3f >= %.3f",
               throughput, min_throughput);
    else if (errors == 0)
      $display("FAIL: Throughput %.3f below threshold %.3f",
               throughput, min_throughput);
    else
      $display("FAIL: %0d mismatches detected", errors);

    $finish;
  end

  // ================================================================
  // Basic run-time checks (instead of full SV assertions)
  // ================================================================
  always @(posedge clk_i) begin
    if (!reset_i) begin
      if (valid_i && !ready_o)
        $display("Warning: valid_i high but ready_o low at t=%0t", $time);
      if (valid_o && !yumi_i)
        $display("Warning: output valid_o not consumed at t=%0t", $time);
    end
  end

  // ================================================================
  // Waveform Dump
  // ================================================================
  initial begin
    $dumpfile("systolic_array_throughput.vcd");
    $dumpvars(0, systolic_array_tb);
  end

endmodule
