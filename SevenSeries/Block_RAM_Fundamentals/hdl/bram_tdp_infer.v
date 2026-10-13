`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bram_tdp_infer
//
// The same 1K x 18 true dual-port RAM as bram_tdp_prim.v, written as plain RTL
// so that Vivado synthesis infers a RAMB18E1.
//
// Things to notice:
//   * Each port has its own always block. That is what tells synthesis it
//     is a true dual-port memory.
//   * The read is registered ("lat_*"). This is the BRAM's built-in output
//     latch. An asynchronous read would infer LUTRAM instead.
//   * The write mode comes from how the read is coded relative to the write:
//       WRITE_FIRST : output the data being written
//       READ_FIRST  : output the old contents
//       NO_CHANGE   : do not update the output during a write
//   * The optional second register ("q_*") is absorbed into DOA_REG/DOB_REG.
//   * Only the output is reset, never the memory array.
//------------------------------------------------------------------------------
module bram_tdp_infer #(
  parameter        WRITE_MODE = "READ_FIRST", // "WRITE_FIRST", "READ_FIRST" or "NO_CHANGE"
  parameter        DO_REG     = 1,            // 0: read latency 1, 1: read latency 2
  parameter [17:0] SRVAL      = 18'h2BEEF     // output value after a reset
)(
  // Port A
  input  wire        clk_a,
  input  wire        en_a,
  input  wire        we_a,
  input  wire        rst_a,
  input  wire [9:0]  addr_a,
  input  wire [17:0] din_a,
  output wire [17:0] dout_a,
  // Port B
  input  wire        clk_b,
  input  wire        en_b,
  input  wire        we_b,
  input  wire        rst_b,
  input  wire [9:0]  addr_b,
  input  wire [17:0] din_b,
  output wire [17:0] dout_b
);

  (* ram_style = "block" *) reg [17:0] mem [0:1023];

  integer i;
  initial for (i = 0; i < 1024; i = i + 1) mem[i] = 18'h00000;

  // Without the output register, reset goes to the latch (RSTRAM).
  wire rst_lat_a = (DO_REG == 0) && rst_a;
  wire rst_lat_b = (DO_REG == 0) && rst_b;

  reg [17:0] lat_a = 18'h00000;
  reg [17:0] lat_b = 18'h00000;

  always @(posedge clk_a)
    if (en_a) begin
      if (we_a)
        mem[addr_a] <= din_a;
      if (rst_lat_a)
        lat_a <= SRVAL;
      else if (WRITE_MODE == "WRITE_FIRST")
        lat_a <= we_a ? din_a : mem[addr_a];
      else if (WRITE_MODE == "READ_FIRST")
        lat_a <= mem[addr_a];
      else if (!we_a)                         // NO_CHANGE
        lat_a <= mem[addr_a];
    end

  always @(posedge clk_b)
    if (en_b) begin
      if (we_b)
        mem[addr_b] <= din_b;
      if (rst_lat_b)
        lat_b <= SRVAL;
      else if (WRITE_MODE == "WRITE_FIRST")
        lat_b <= we_b ? din_b : mem[addr_b];
      else if (WRITE_MODE == "READ_FIRST")
        lat_b <= mem[addr_b];
      else if (!we_b)                         // NO_CHANGE
        lat_b <= mem[addr_b];
    end

  generate
    if (DO_REG != 0) begin : g_doreg
      // With the output register, reset goes to the register (RSTREG).
      reg [17:0] q_a = 18'h00000;
      reg [17:0] q_b = 18'h00000;

      always @(posedge clk_a)
        if (rst_a) q_a <= SRVAL;
        else       q_a <= lat_a;

      always @(posedge clk_b)
        if (rst_b) q_b <= SRVAL;
        else       q_b <= lat_b;

      assign dout_a = q_a;
      assign dout_b = q_b;
    end else begin : g_nodoreg
      assign dout_a = lat_a;
      assign dout_b = lat_b;
    end
  endgenerate

endmodule
