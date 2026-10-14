`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_bram_tdp
//
// Instantiates six copies of the 1K x 18 TDP RAM:
//     {WRITE_FIRST, READ_FIRST, NO_CHANGE} x {DO_REG = 0, DO_REG = 1}
// Each copy contains both the RAMB18E1 primitive and the inferred RTL version.
//
// Phase 1 (directed): writes, reads, a read-during-write, and a reset. The
//                     testbench prints what every configuration returns and
//                     checks it against the expected value.
// Phase 2 (random):   random traffic on both ports. Port A uses addresses
//                     0-511 and port B uses 512-1023, so the ports never
//                     collide. The primitive and the inferred RAM are compared
//                     on every clock cycle.
//
// Needs the UNISIM library and glbl (see run_xsim.sh). glbl holds GSR high for
// the first 100 ns, so nothing is checked before 200 ns.
//------------------------------------------------------------------------------
module tb_bram_tdp;

  localparam [17:0] SRVAL = 18'h2BEEF;

  reg clk = 1'b0;
  always #5 clk = ~clk;   // 100 MHz, for easy waveform reading

  reg        en_a = 0, we_a = 0, rst_a = 0;
  reg [9:0]  addr_a = 0;
  reg [17:0] din_a = 0;
  reg        en_b = 0, we_b = 0, rst_b = 0;
  reg [9:0]  addr_b = 0;
  reg [17:0] din_b = 0;

  // Directed checks: set for one cycle together with the operation to check.
  reg        chk_a = 0;                 // check port A read data
  reg [17:0] exp_wf = 0, exp_rf = 0, exp_nc = 0;
  reg        chk_b = 0;                 // check port B read data
  reg [17:0] exp_b = 0;
  reg        chk_rst = 0;               // check port A shows SRVAL after reset
  reg        compare_on = 0;

  `define TDP_PAIR(NAME, MODE, REG) \
    tdp_pair #(.WRITE_MODE(MODE), .DO_REG(REG), .SRVAL(SRVAL)) NAME ( \
      .clk(clk), \
      .en_a(en_a), .we_a(we_a), .rst_a(rst_a), .addr_a(addr_a), .din_a(din_a), \
      .en_b(en_b), .we_b(we_b), .rst_b(rst_b), .addr_b(addr_b), .din_b(din_b), \
      .chk_a(chk_a), .exp_wf(exp_wf), .exp_rf(exp_rf), .exp_nc(exp_nc), \
      .chk_b(chk_b), .exp_b(exp_b), .chk_rst(chk_rst), .compare_on(compare_on));

  `TDP_PAIR(u_wf_r0, "WRITE_FIRST", 0)
  `TDP_PAIR(u_wf_r1, "WRITE_FIRST", 1)
  `TDP_PAIR(u_rf_r0, "READ_FIRST",  0)
  `TDP_PAIR(u_rf_r1, "READ_FIRST",  1)
  `TDP_PAIR(u_nc_r0, "NO_CHANGE",   0)
  `TDP_PAIR(u_nc_r1, "NO_CHANGE",   1)

  // One cycle of stimulus, applied on the falling edge.
  task op_a(input en, input we, input rst, input [9:0] addr, input [17:0] din);
    begin
      @(negedge clk);
      en_a = en; we_a = we; rst_a = rst; addr_a = addr; din_a = din;
      en_b = 0;  we_b = 0;  rst_b = 0;
      chk_a = 0; chk_b = 0; chk_rst = 0;
    end
  endtask

  integer n;
  integer errors=0;
  reg     test_passed = 1'b0;   // read by scripts/run_sim.tcl

  initial begin
    $display("--------------------------------------------------------------");
    $display(" 7 Series RAMB18E1: primitive vs inferred, all write modes");
    $display("--------------------------------------------------------------");

    #200;               // wait for GSR to release
    compare_on = 1;

    // ---- Phase 1: directed --------------------------------------------
    op_a(1, 1, 0, 10'd5, 18'h00011);          // write  mem[5] = 0x11
    op_a(1, 1, 0, 10'd6, 18'h00022);          // write  mem[6] = 0x22

    op_a(1, 0, 0, 10'd5, 18'h0);              // read mem[5]
    chk_a = 1; exp_wf = 18'h11; exp_rf = 18'h11; exp_nc = 18'h11;

    op_a(1, 0, 0, 10'd6, 18'h0);              // read mem[6]
    chk_a = 1; exp_wf = 18'h22; exp_rf = 18'h22; exp_nc = 18'h22;

    // Read-during-write: write 0x55 to address 5, which currently holds 0x11.
    //   WRITE_FIRST -> 0x55 (the new data)
    //   READ_FIRST  -> 0x11 (the old data)
    //   NO_CHANGE   -> 0x22 (the output keeps the previous read)
    op_a(1, 1, 0, 10'd5, 18'h00055);
    chk_a = 1; exp_wf = 18'h55; exp_rf = 18'h11; exp_nc = 18'h22;

    op_a(0, 0, 0, 10'd0, 18'h0);              // idle: the output holds

    // Synchronous reset of the output. Asserted with EN high and WE low.
    op_a(1, 0, 1, 10'd6, 18'h0);
    chk_rst = 1;

    op_a(0, 0, 0, 10'd0, 18'h0);

    // Port B reads back what port A wrote (true dual port).
    @(negedge clk);
    en_a = 0; we_a = 0; rst_a = 0; chk_a = 0; chk_rst = 0;
    en_b = 1; we_b = 0; addr_b = 10'd5;
    chk_b = 1; exp_b = 18'h55;

    @(negedge clk);
    en_b = 0; chk_b = 0;
    repeat (4) @(negedge clk);

    // ---- Phase 2: random, primitive vs inferred ------------------------
    $display("Random phase: 5000 cycles, comparing primitive vs inferred...");
    for (n = 0; n < 5000; n = n + 1) begin
      @(negedge clk);
      chk_a = 0; chk_b = 0; chk_rst = 0;

      en_a   = ($random & 3) != 0;
      we_a   = $random;
      addr_a = {1'b0, $random} & 10'h1FF;
      din_a  = $random;
      rst_a  = en_a && !we_a && (($random & 31) == 0);

      en_b   = ($random & 3) != 0;
      we_b   = $random;
      addr_b = {1'b1, 9'h000} | ($random & 10'h1FF);
      din_b  = $random;
      rst_b  = en_b && !we_b && (($random & 31) == 0);
    end

    @(negedge clk);
    en_a = 0; we_a = 0; rst_a = 0; en_b = 0; we_b = 0; rst_b = 0;
    repeat (4) @(negedge clk);

    errors = u_wf_r0.errors + u_wf_r1.errors + u_rf_r0.errors +
             u_rf_r1.errors + u_nc_r0.errors + u_nc_r1.errors;

    $display("--------------------------------------------------------------");
    test_passed = (errors == 0);
    if (test_passed) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("--------------------------------------------------------------");
    $finish;
  end

endmodule

//------------------------------------------------------------------------------
// One primitive + one inferred RAM with the same configuration, and checkers.
//------------------------------------------------------------------------------
module tdp_pair #(
  parameter        WRITE_MODE = "READ_FIRST",
  parameter        DO_REG     = 1,
  parameter [17:0] SRVAL      = 18'h2BEEF
)(
  input wire        clk,
  input wire        en_a, we_a, rst_a,
  input wire [9:0]  addr_a,
  input wire [17:0] din_a,
  input wire        en_b, we_b, rst_b,
  input wire [9:0]  addr_b,
  input wire [17:0] din_b,
  input wire        chk_a,
  input wire [17:0] exp_wf, exp_rf, exp_nc,
  input wire        chk_b,
  input wire [17:0] exp_b,
  input wire        chk_rst,
  input wire        compare_on
);

  localparam LAT = (DO_REG != 0) ? 2 : 1;

  wire [17:0] prim_a, prim_b, infer_a, infer_b;

  bram_tdp_prim #(.WRITE_MODE(WRITE_MODE), .DO_REG(DO_REG), .SRVAL(SRVAL)) u_prim (
    .clk_a(clk), .en_a(en_a), .we_a(we_a), .rst_a(rst_a), .addr_a(addr_a), .din_a(din_a), .dout_a(prim_a),
    .clk_b(clk), .en_b(en_b), .we_b(we_b), .rst_b(rst_b), .addr_b(addr_b), .din_b(din_b), .dout_b(prim_b)
  );

  bram_tdp_infer #(.WRITE_MODE(WRITE_MODE), .DO_REG(DO_REG), .SRVAL(SRVAL)) u_infer (
    .clk_a(clk), .en_a(en_a), .we_a(we_a), .rst_a(rst_a), .addr_a(addr_a), .din_a(din_a), .dout_a(infer_a),
    .clk_b(clk), .en_b(en_b), .we_b(we_b), .rst_b(rst_b), .addr_b(addr_b), .din_b(din_b), .dout_b(infer_b)
  );

  wire [17:0] exp_mode = (WRITE_MODE == "WRITE_FIRST") ? exp_wf :
                         (WRITE_MODE == "READ_FIRST")  ? exp_rf : exp_nc;

  // Delay the directed checks by the read latency of this configuration.
  reg [1:0]  chk_a_sr = 0, chk_b_sr = 0;
  reg [17:0] exp_a_sr0 = 0, exp_a_sr1 = 0, exp_b_sr0 = 0, exp_b_sr1 = 0;
  reg        rst_sr = 0;

  always @(posedge clk) begin
    chk_a_sr  <= {chk_a_sr[0], chk_a};
    exp_a_sr0 <= exp_mode;
    exp_a_sr1 <= exp_a_sr0;
    chk_b_sr  <= {chk_b_sr[0], chk_b};
    exp_b_sr0 <= exp_b;
    exp_b_sr1 <= exp_b_sr0;
    rst_sr    <= chk_rst;   // reset reaches the output after 1 cycle, whatever DO_REG is
  end

  wire        chk_a_now = chk_a_sr[LAT-1];
  wire [17:0] exp_a_now = (LAT == 1) ? exp_a_sr0 : exp_a_sr1;
  wire        chk_b_now = chk_b_sr[LAT-1];
  wire [17:0] exp_b_now = (LAT == 1) ? exp_b_sr0 : exp_b_sr1;

  integer errors = 0;

  always @(negedge clk) if (compare_on) begin
    if (prim_a !== infer_a || prim_b !== infer_b) begin
      errors = errors + 1;
      $display("%t [%0s DO_REG=%0d] MISMATCH prim A=%h B=%h  infer A=%h B=%h",
               $time, WRITE_MODE, DO_REG, prim_a, prim_b, infer_a, infer_b);
    end

    if (chk_a_now) begin
      $display("%t [%11s DO_REG=%0d] port A read = %h (expected %h) %0s",
               $time, WRITE_MODE, DO_REG, prim_a, exp_a_now,
               (prim_a === exp_a_now) ? "OK" : "ERROR");
      if (prim_a !== exp_a_now) errors = errors + 1;
    end

    if (chk_b_now) begin
      $display("%t [%11s DO_REG=%0d] port B read = %h (expected %h) %0s",
               $time, WRITE_MODE, DO_REG, prim_b, exp_b_now,
               (prim_b === exp_b_now) ? "OK" : "ERROR");
      if (prim_b !== exp_b_now) errors = errors + 1;
    end

    if (rst_sr) begin
      $display("%t [%11s DO_REG=%0d] after reset  = %h (expected SRVAL %h) %0s",
               $time, WRITE_MODE, DO_REG, prim_a, SRVAL,
               (prim_a === SRVAL) ? "OK" : "ERROR");
      if (prim_a !== SRVAL) errors = errors + 1;
    end
  end

endmodule
