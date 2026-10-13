`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bram_tdp_prim
//
// 1K x 18 true dual-port RAM built by directly instantiating a 7 Series
// RAMB18E1 primitive. Functionally identical to bram_tdp_infer.v so the two
// can be compared cycle-for-cycle in simulation.
//
// Things to notice:
//   * ADDRARDADDR / ADDRBWRADDR are always 14 bits. In x18 mode only bits
//     [13:4] are used, so the 10-bit address is shifted left by 4.
//   * The 18-bit word is split into 16 data bits (DIADI/DOADO) and
//     2 "parity" bits (DIPADIP/DOPADOP). The parity bits are ordinary storage.
//   * With DO_REG = 0 the reset input drives RSTRAM (the output latch).
//     With DO_REG = 1 it drives RSTREG (the optional output register).
//     The memory array itself can never be reset.
//------------------------------------------------------------------------------
module bram_tdp_prim #(
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

  wire rstram_a = (DO_REG == 0) ? rst_a : 1'b0;
  wire rstreg_a = (DO_REG != 0) ? rst_a : 1'b0;
  wire rstram_b = (DO_REG == 0) ? rst_b : 1'b0;
  wire rstreg_b = (DO_REG != 0) ? rst_b : 1'b0;

  RAMB18E1 #(
    .RAM_MODE                  ("TDP"),
    .READ_WIDTH_A              (18),
    .WRITE_WIDTH_A             (18),
    .READ_WIDTH_B              (18),
    .WRITE_WIDTH_B             (18),
    .DOA_REG                   (DO_REG),
    .DOB_REG                   (DO_REG),
    .WRITE_MODE_A              (WRITE_MODE),
    .WRITE_MODE_B              (WRITE_MODE),
    .INIT_A                    (18'h00000),
    .INIT_B                    (18'h00000),
    .SRVAL_A                   (SRVAL),
    .SRVAL_B                   (SRVAL),
    .RSTREG_PRIORITY_A         ("RSTREG"),    // reset wins over REGCE
    .RSTREG_PRIORITY_B         ("RSTREG"),
    .RDADDR_COLLISION_HWCONFIG ("DELAYED_WRITE"),
    .SIM_COLLISION_CHECK       ("ALL"),       // warn in simulation on port collisions
    .SIM_DEVICE                ("7SERIES")
  ) u_ramb18 (
    // Port A
    .CLKARDCLK     (clk_a),
    .ENARDEN       (en_a),
    .REGCEAREGCE   (1'b1),
    .RSTRAMARSTRAM (rstram_a),
    .RSTREGARSTREG (rstreg_a),
    .WEA           ({2{we_a}}),             // one enable per byte (9 bits each)
    .ADDRARDADDR   ({addr_a, 4'b0000}),     // x18: address bits [13:4]
    .DIADI         (din_a[15:0]),
    .DIPADIP       (din_a[17:16]),
    .DOADO         (dout_a[15:0]),
    .DOPADOP       (dout_a[17:16]),
    // Port B
    .CLKBWRCLK     (clk_b),
    .ENBWREN       (en_b),
    .REGCEB        (1'b1),
    .RSTRAMB       (rstram_b),
    .RSTREGB       (rstreg_b),
    .WEBWE         ({2'b00, {2{we_b}}}),    // TDP uses WEBWE[1:0]; [3:2] are for SDP x36
    .ADDRBWRADDR   ({addr_b, 4'b0000}),
    .DIBDI         (din_b[15:0]),
    .DIPBDIP       (din_b[17:16]),
    .DOBDO         (dout_b[15:0]),
    .DOPBDOP       (dout_b[17:16])
  );

endmodule
