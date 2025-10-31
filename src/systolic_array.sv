// A driver for the systolic array module.
`timescale 1ns / 1ps

module systolic_array
#(
  parameter width_p        = 32,
  parameter array_width_p  = 8,
  parameter array_height_p = 8
)
(
  input  logic        clk_i,
  input  logic        reset_i,
  input  logic        en_i,
  input  logic        flush_i,

  // Consumer interface
  output logic        ready_o,
  input  logic        valid_i,
  input  logic [width_p-1:0] data_i,

  // Producer interface
  output logic        valid_o,
  input  logic        yumi_i,
  output logic [width_p-1:0] data_o,

  // DEBUG ONLY
  output logic        busy_o,
  output logic        idle_o,
  output logic [7:0]  onehot_o
);

  localparam int num_consumers_lp = array_width_p + array_height_p;
  localparam int num_macs_lp      = array_width_p * array_height_p;
  localparam int flush_cnt_w      = $clog2((num_macs_lp>1)?num_macs_lp:2);

  /*
   * This module assumes that the next MAC consumer is ready by the time the
   * onehot_counter selects it for input. This assumption is dependent on the
   * implementation of mac.sv.
   *
   * Since the systolic_array module doesn't currently support flushing, this
   * top module instead resets the entire systolic_array before passing in
   * a new pair of matrices.
   */

  typedef enum logic [4:0] {
      IDLE_S   = 5'b00001,
      INPUT_S  = 5'b00010,
      BUSY_S   = 5'b00100,
      FLUSH_S  = 5'b01000,
      F_DONE_S = 5'b10000
  } state_e;

  state_e state_r, state_n;

  // Wires/regs
  wire [num_consumers_lp-1:0] onehot_w;
  wire [flush_cnt_w-1:0]      flush_count_w;
  wire [array_height_p-1:0]   row_valid_i, row_ready_o;
  wire [array_width_p-1:0]    col_valid_i, col_ready_o;
  wire [(width_p*array_height_p)-1:0] row_i;
  wire [(width_p*array_width_p)-1:0]  col_i;
  wire                             hottest_bit_w, all_consumers_ready_w;
  wire                             flush_done_w, flush_array_w;
  wire                             reset_onehot_w;

  // All MAC results (flattened)
  wire [(width_p*num_macs_lp)-1:0] z_w;

  // Handshake vectors from mac_array (generalized to num_macs_lp)
  wire [num_macs_lp-1:0] z_valid_throwaway_w;
  wire [num_macs_lp-1:0] z_yumi_throwaway_w;

  // FSM next-state logic (pattern matches preserved)
  always_comb begin
    unique casez ({
      state_r,
      valid_i,
      flush_i,
      hottest_bit_w,
      all_consumers_ready_w,
      flush_done_w
    })
      {IDLE_S,   5'b10???} : state_n = INPUT_S;
      {INPUT_S,  5'b1?1??} : state_n = BUSY_S;
      {BUSY_S,   5'b???1?} : state_n = IDLE_S;
      {IDLE_S,   5'b01???} : state_n = FLUSH_S;
      {FLUSH_S,  5'b????1} : state_n = F_DONE_S;
      {F_DONE_S, 5'b?????} : state_n = IDLE_S;
      default               : state_n = state_r;
    endcase
  end

  assign busy_o = (state_r == BUSY_S);
  assign idle_o = (state_r == IDLE_S);

  // Show lower 8 bits of onehot (debug only); avoids width warnings for 8x8 (16b onehot)
  assign onehot_o = onehot_w[7:0];

  // FSM state reg
  always_ff @(posedge clk_i) begin
    if (reset_i)       state_r <= IDLE_S;
    else if (en_i)     state_r <= state_n;
  end

  // Distribute data/valids to rows & cols; onehot gates which consumer sees valid_i
  assign {row_valid_i, col_valid_i} = onehot_w & {num_consumers_lp{valid_i}};
  assign row_i = {array_height_p{data_i}};
  assign col_i = {array_width_p{data_i}};

  // MSB of onehot indicates all consumers have received a valid this input step.
  assign hottest_bit_w          = onehot_w[num_consumers_lp-1];
  assign all_consumers_ready_w  = (&row_ready_o & &col_ready_o);
  assign flush_done_w           = (flush_count_w == (num_macs_lp-1));
  assign flush_array_w          = (state_r == F_DONE_S);
  assign reset_onehot_w         = ((state_r == IDLE_S) & valid_i);

  // Producer/consumer side ready/valid
  assign ready_o = ((state_r == IDLE_S) | (state_r == INPUT_S));
  assign valid_o = (state_r == FLUSH_S);

  // Slow enable to give MACs an extra cycle to latch inputs
  logic slow_en_r;
  always_ff @(posedge clk_i) begin
    if (reset_i)               slow_en_r <= 1'b0;
    else if (en_i & valid_i)   slow_en_r <= ~slow_en_r;
  end

  // One-hot counter (width = num_consumers_lp)
  onehot_counter
  #(num_consumers_lp)
  onehot_counter_inst
  (
    .clk_i   (clk_i),
    // .en_i (en_i & valid_i)
    .en_i    (en_i & slow_en_r),
    .reset_i (reset_i | reset_onehot_w),
    .count_o (onehot_w)
  );

  // Flush counter (counts MAC results to emit during FLUSH)
  counter
  #(flush_cnt_w)
  flush_counter_inst
  (
    .clk_i   (clk_i),
    .en_i    (en_i & (state_r == FLUSH_S)),
    .reset_i (reset_i | flush_i),
    .count_o (flush_count_w)
  );

  // MAC array
  mac_array
  #(
    .width_p        (width_p),
    .array_width_p  (array_width_p),
    .array_height_p (array_height_p)
  )
  mac_array_inst
  (
    .clk_i        (clk_i),
    .reset_i      (reset_i | flush_array_w),
    .en_i         (en_i),
    .row_i        (row_i),
    .row_valid_i  (row_valid_i),
    .row_ready_o  (row_ready_o),
    .col_i        (col_i),
    .col_valid_i  (col_valid_i),
    .col_ready_o  (col_ready_o),
    .z_o          (z_w),
    .z_valid_o    (z_valid_throwaway_w), // [num_macs_lp-1:0]
    .z_yumi_i     (z_yumi_throwaway_w)   // [num_macs_lp-1:0]
  );

  // -------- Generalized output mux (replaces 2x2 hard-code) --------
  // Emit one MAC result per FLUSH step: select word 'flush_count_w'
  logic [width_p-1:0] data_o_l;
  always_comb begin
    if (flush_count_w < num_macs_lp)
      // variable part-select: pick the (flush_count_w)-th word of z_w
      data_o_l = z_w[(flush_count_w+1)*width_p-1 -: width_p];
    else
      data_o_l = '0;
  end

  assign data_o = data_o_l;

endmodule
