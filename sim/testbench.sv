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

  // ================================================================
  // Randomization Constraints
  // ================================================================
  typedef struct {
    rand bit [width_p-1:0] value;
    rand bit valid;
    constraint c_valid {
      valid dist {1 := 80, 0 := 20}; // 80% chance of sending data
    }
  } input_packet_t;

  input_packet_t packet;

  // ================================================================
  // Reference Model Variables
  // ================================================================
  int golden_output [$];     // dynamic array for expected outputs
  int received_output [$];   // DUT outputs for comparison

  // ================================================================
  // Throughput Measurement Variables
  // ================================================================
  int total_cycles;
  int output_count;
  realtime start_time, end_time;
  real throughput;
  real min_throughput = 0.50; // minimum acceptable throughput

  // ================================================================
  // Assertions
  // ================================================================
  // ready_o must assert within 3 cycles of valid_i
  property ready_within_3;
    @(posedge clk_i) disable iff (reset_i)
      valid_i |-> ##[1:3] ready_o;
  endproperty
  assert_ready_within_3: assert property (ready_within_3)
    else $error("ready_o did not assert within 3 cycles of valid_i");

  // data_i must remain stable while ready_o is low
  property data_stable_while_wait;
    @(posedge clk_i) disable iff (reset_i)
      (valid_i && !ready_o) |=> (data_i == $past(data_i));
  endproperty
  assert_data_stable_while_wait: assert property (data_stable_while_wait)
    else $error("data_i changed while ready_o was low");

  // valid_o should be followed by yumi_i within 3 cycles
  property output_consumed;
    @(posedge clk_i) disable iff (reset_i)
      valid_o |-> ##[1:3] yumi_i;
  endproperty
  assert_output_consumed: assert property (output_consumed)
    else $warning("Output not consumed quickly by yumi_i");

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

    // simple golden model: store all data_i values
    golden_output.delete();
    received_output.delete();

    start_time = $realtime;

    repeat (500) begin
      void'(packet.randomize());
      valid_i = packet.valid;
      data_i  = packet.value;

      // generate a simple reference pattern (for demonstration)
      if (valid_i)
        golden_output.push_back(data_i); // expected sequence

      // output handshake
      yumi_i = valid_o;

      @(posedge clk_i);
      total_cycles++;

      if (valid_o && yumi_i) begin
        received_output.push_back(data_o);
        output_count++;
      end
    end

    end_time = $realtime;
    flush_i = 1;
    repeat (5) @(posedge clk_i);
    flush_i = 0;

    throughput = (output_count * 1.0) / total_cycles;
    $display("----------------------------------------------------------");
    $display("Total cycles       : %0d", total_cycles);
    $display("Total outputs      : %0d", output_count);
    $display("Throughput (out/clk): %0.3f", throughput);
    $display("----------------------------------------------------------");

    // ============================================================
    // Functional Comparison
    // ============================================================
    int errors = 0;
    int min_size = (golden_output.size() < received_output.size()) ?
                   golden_output.size() : received_output.size();
    for (int i = 0; i < min_size; i++) begin
      if (received_output[i] !== golden_output[i]) begin
        $display("Mismatch at output[%0d]: expected=%0d got=%0d",
                  i, golden_output[i], received_output[i]);
        errors++;
      end
    end

    // ============================================================
    // Pass/Fail Logic
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
  // Waveform
  // ================================================================
  initial begin
    $dumpfile("systolic_array_throughput.vcd");
    $dumpvars(0, systolic_array_tb);
  end

endmodule
