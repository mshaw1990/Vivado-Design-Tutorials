`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bram_deep_buffer
//
// A deep simple dual-port buffer (default 64K x 32 = 2 Mb, 64 banks) built from
// many 1K-deep BRAM banks and pipelined for high Fmax on a large SSI device
// such as the XC7V2000T.
//
// Pipeline (read latency = 5 + LEVELS clock cycles, see LATENCY below):
//
//   A  input registers
//   B  address/data/enable registers duplicated once per GROUP banks
//      (DONT_TOUCH stops synthesis merging the copies back together),
//      so no single register drives every BRAM in the device
//   C  BRAM output latch      (only the addressed bank is enabled)
//   D  BRAM output register   (DOB_REG)
//   E  zero every bank output except the one that was read
//   F  radix-4 OR tree, one register per level (LEVELS = ceil(log4(NB)))
//
// Writes go through the same A/B stages, so a read issued in the cycle after a
// write to the same address returns the new data. A read and a write to the
// same address in the same cycle is a BRAM collision and returns undefined data.
//
// Requirements: AW > BANK_AW.
//------------------------------------------------------------------------------
module bram_deep_buffer #(
  parameter DW      = 32,
  parameter AW      = 16,   // total depth = 2**AW words
  parameter BANK_AW = 10,   // each bank is 2**BANK_AW words deep
  parameter GROUP   = 8     // banks served by each copy of the stage-B registers
)(
  input  wire          clk,
  input  wire          wr_en,
  input  wire [AW-1:0] wr_addr,
  input  wire [DW-1:0] wr_data,
  input  wire          rd_en,
  input  wire [AW-1:0] rd_addr,
  output wire          rd_valid,
  output wire [DW-1:0] rd_data
);

  function integer clog4;
    input integer n;
    integer v;
    begin
      clog4 = 0;
      v     = 1;
      while (v < n) begin
        v     = v * 4;
        clog4 = clog4 + 1;
      end
    end
  endfunction

  localparam NB      = 1 << (AW - BANK_AW);      // number of banks
  localparam NG      = (NB + GROUP - 1) / GROUP; // number of register copies
  localparam LEVELS  = clog4(NB);                // OR-tree depth
  localparam LATENCY = 5 + LEVELS;

  //--------------------------------------------------------------------------
  // Stage A: input registers
  //--------------------------------------------------------------------------
  reg          wr_en_a   = 1'b0;
  reg          rd_en_a   = 1'b0;
  reg [AW-1:0] wr_addr_a = {AW{1'b0}};
  reg [AW-1:0] rd_addr_a = {AW{1'b0}};
  reg [DW-1:0] wr_data_a = {DW{1'b0}};

  always @(posedge clk) begin
    wr_en_a   <= wr_en;
    rd_en_a   <= rd_en;
    wr_addr_a <= wr_addr;
    rd_addr_a <= rd_addr;
    wr_data_a <= wr_data;
  end

  //--------------------------------------------------------------------------
  // Stage B (register copies) and stages C/D (the BRAM banks)
  //--------------------------------------------------------------------------
  wire [NB*DW-1:0] bank_dout;
  wire [NB-1:0]    bank_sel;    // high on the bank whose read data is at stage D

  genvar g, b;
  generate
    for (g = 0; g < NG; g = g + 1) begin : g_grp
      (* dont_touch = "true" *) reg          wr_en_b   = 1'b0;
      (* dont_touch = "true" *) reg          rd_en_b   = 1'b0;
      (* dont_touch = "true" *) reg [AW-1:0] wr_addr_b = {AW{1'b0}};
      (* dont_touch = "true" *) reg [AW-1:0] rd_addr_b = {AW{1'b0}};
      (* dont_touch = "true" *) reg [DW-1:0] wr_data_b = {DW{1'b0}};

      always @(posedge clk) begin
        wr_en_b   <= wr_en_a;
        rd_en_b   <= rd_en_a;
        wr_addr_b <= wr_addr_a;
        rd_addr_b <= rd_addr_a;
        wr_data_b <= wr_data_a;
      end

      for (b = g * GROUP; (b < (g + 1) * GROUP) && (b < NB); b = b + 1) begin : g_bank
        wire we = wr_en_b && (wr_addr_b[AW-1:BANK_AW] == b);
        wire re = rd_en_b && (rd_addr_b[AW-1:BANK_AW] == b);

        bram_sdp_bank #(.DW(DW), .AW(BANK_AW)) u_bank (
          .clk   (clk),
          .we    (we),
          .waddr (wr_addr_b[BANK_AW-1:0]),
          .din   (wr_data_b),
          .re    (re),
          .raddr (rd_addr_b[BANK_AW-1:0]),
          .dout  (bank_dout[b*DW +: DW])
        );

        // Track which bank was read, aligned with the BRAM's two-cycle latency.
        reg sel_c = 1'b0;
        reg sel_d = 1'b0;
        always @(posedge clk) begin
          sel_c <= re;
          sel_d <= sel_c;
        end
        assign bank_sel[b] = sel_d;
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // Stage E and F: gate the bank outputs, then a registered radix-4 OR tree.
  // Banks that were not read hold stale data in their output registers, so
  // they must be zeroed before the OR.
  // tree holds LEVELS+1 levels of NB words. Unused entries are constant zero
  // and are removed by synthesis.
  //--------------------------------------------------------------------------
  reg [(LEVELS+1)*NB*DW-1:0] tree = {((LEVELS+1)*NB*DW){1'b0}};
  reg [DW-1:0]               acc;
  integer                    l, k, j;

  always @(posedge clk) begin
    for (k = 0; k < NB; k = k + 1)
      tree[k*DW +: DW] <= bank_dout[k*DW +: DW] & {DW{bank_sel[k]}};

    for (l = 1; l <= LEVELS; l = l + 1)
      for (k = 0; k < NB; k = k + 1) begin
        acc = {DW{1'b0}};
        for (j = 0; j < 4; j = j + 1)
          if (4*k + j < NB)
            acc = acc | tree[((l-1)*NB + 4*k + j)*DW +: DW];
        tree[(l*NB + k)*DW +: DW] <= acc;
      end
  end

  assign rd_data = tree[LEVELS*NB*DW +: DW];

  //--------------------------------------------------------------------------
  // Read-valid pipeline
  //--------------------------------------------------------------------------
  reg [LATENCY-1:0] vld = {LATENCY{1'b0}};
  always @(posedge clk)
    vld <= {vld[LATENCY-2:0], rd_en};

  assign rd_valid = vld[LATENCY-1];

endmodule
