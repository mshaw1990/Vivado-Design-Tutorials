`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bram_sdp_bank
//
// Simple dual-port (one write port, one read port), single-clock RAM using the
// standard Vivado inference template with the output register enabled.
// Read latency is 2: re/raddr -> output latch -> DO register.
//
// With the defaults (1K x 32), each bank maps to a single RAMB36E1 in 1K x 36
// mode, or to two RAMB18E1s. Check the synthesis log to see which.
//------------------------------------------------------------------------------
module bram_sdp_bank #(
  parameter DW = 32,
  parameter AW = 10
)(
  input  wire          clk,
  input  wire          we,
  input  wire [AW-1:0] waddr,
  input  wire [DW-1:0] din,
  input  wire          re,
  input  wire [AW-1:0] raddr,
  output reg  [DW-1:0] dout
);

  (* ram_style = "block" *) reg [DW-1:0] mem [0:(1<<AW)-1];
  reg [DW-1:0] rdata;

  integer i;
  initial begin
    for (i = 0; i < (1<<AW); i = i + 1) mem[i] = {DW{1'b0}};
    rdata = {DW{1'b0}};
    dout  = {DW{1'b0}};
  end

  always @(posedge clk) begin
    if (we) mem[waddr] <= din;
    if (re) rdata <= mem[raddr];   // output latch, gated by the BRAM enable
    dout <= rdata;                 // absorbed into DOB_REG
  end

endmodule
