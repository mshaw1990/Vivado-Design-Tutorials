`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bram_fmax_harness
//
// Timing harness for the 1K x 18 TDP RAM. All inputs are registered, and the
// two read ports are added together into a register. That creates a real
// BRAM -> fabric logic -> flip-flop path for an out-of-context run to time.
//
// Run it with DO_REG = 0 and DO_REG = 1 to see how much the BRAM output
// register helps Fmax.
//------------------------------------------------------------------------------
module bram_fmax_harness #(
  parameter USE_PRIM   = 0,            // 1: instantiated RAMB18E1, 0: inferred
  parameter DO_REG     = 1,
  parameter WRITE_MODE = "READ_FIRST"
)(
  input  wire        clk,
  input  wire        en_a,
  input  wire        we_a,
  input  wire [9:0]  addr_a,
  input  wire [17:0] din_a,
  input  wire        en_b,
  input  wire        we_b,
  input  wire [9:0]  addr_b,
  input  wire [17:0] din_b,
  output reg  [18:0] sum_q
);

  reg        en_a_q, we_a_q, en_b_q, we_b_q;
  reg [9:0]  addr_a_q, addr_b_q;
  reg [17:0] din_a_q, din_b_q;

  always @(posedge clk) begin
    en_a_q   <= en_a;
    we_a_q   <= we_a;
    addr_a_q <= addr_a;
    din_a_q  <= din_a;
    en_b_q   <= en_b;
    we_b_q   <= we_b;
    addr_b_q <= addr_b;
    din_b_q  <= din_b;
  end

  wire [17:0] dout_a, dout_b;

  generate
    if (USE_PRIM != 0) begin : g_prim
      bram_tdp_prim #(.WRITE_MODE(WRITE_MODE), .DO_REG(DO_REG)) u_ram (
        .clk_a(clk), .en_a(en_a_q), .we_a(we_a_q), .rst_a(1'b0),
        .addr_a(addr_a_q), .din_a(din_a_q), .dout_a(dout_a),
        .clk_b(clk), .en_b(en_b_q), .we_b(we_b_q), .rst_b(1'b0),
        .addr_b(addr_b_q), .din_b(din_b_q), .dout_b(dout_b)
      );
    end else begin : g_infer
      bram_tdp_infer #(.WRITE_MODE(WRITE_MODE), .DO_REG(DO_REG)) u_ram (
        .clk_a(clk), .en_a(en_a_q), .we_a(we_a_q), .rst_a(1'b0),
        .addr_a(addr_a_q), .din_a(din_a_q), .dout_a(dout_a),
        .clk_b(clk), .en_b(en_b_q), .we_b(we_b_q), .rst_b(1'b0),
        .addr_b(addr_b_q), .din_b(din_b_q), .dout_b(dout_b)
      );
    end
  endgenerate

  always @(posedge clk)
    sum_q <= dout_a + dout_b;

endmodule
