`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_bram_deep_buffer
//
// Self-checking testbench for bram_deep_buffer (64K x 32, 64 banks).
//   1. Write the first and last word of every bank, then read them all back
//      back-to-back (this exercises every bank and the whole OR tree).
//   2. Write-then-read the same address in the next cycle.
//   3. Random mixed reads and writes.
// Every read issued is pushed onto an expected-data queue. Each rd_valid pops
// the queue and compares the data.
//------------------------------------------------------------------------------
module tb_bram_deep_buffer;

  localparam DW      = 32;
  localparam AW      = 16;
  localparam BANK_AW = 10;
  localparam DEPTH   = 1 << AW;
  localparam NB      = 1 << (AW - BANK_AW);
  localparam QD      = 1024;               // expected-data queue depth

  reg clk = 1'b0;
  always #2 clk = ~clk;

  reg          wr_en = 0, rd_en = 0;
  reg [AW-1:0] wr_addr = 0, rd_addr = 0;
  reg [DW-1:0] wr_data = 0;
  wire         rd_valid;
  wire [DW-1:0] rd_data;

  bram_deep_buffer #(.DW(DW), .AW(AW), .BANK_AW(BANK_AW)) dut (
    .clk(clk),
    .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
    .rd_en(rd_en), .rd_addr(rd_addr),
    .rd_valid(rd_valid), .rd_data(rd_data)
  );

  reg [DW-1:0] model [0:DEPTH-1];
  reg [DW-1:0] expq  [0:QD-1];
  reg [AW-1:0] addrq [0:QD-1];
  integer wp = 0, rp = 0, errors = 0, i, b;
  reg     test_passed = 1'b0;   // read by scripts/run_sim.tcl

  initial for (i = 0; i < DEPTH; i = i + 1) model[i] = {DW{1'b0}};

  // One cycle of stimulus, applied on the falling edge.
  task cycle(input w, input [AW-1:0] wa, input [DW-1:0] wd,
             input r, input [AW-1:0] ra);
    begin
      @(negedge clk);
      wr_en = w; wr_addr = wa; wr_data = wd;
      rd_en = r; rd_addr = ra;
      if (r) begin
        expq[wp % QD]  = model[ra];
        addrq[wp % QD] = ra;
        wp = wp + 1;
      end
      if (w) model[wa] = wd;   // visible to reads issued from the next cycle on
    end
  endtask

  // Scoreboard
  always @(negedge clk)
    if (rd_valid) begin
      if (rd_data !== expq[rp % QD]) begin
        errors = errors + 1;
        if (errors <= 20)
          $display("%t ERROR addr %h: got %h expected %h",
                   $time, addrq[rp % QD], rd_data, expq[rp % QD]);
      end
      rp = rp + 1;
    end

  reg [AW-1:0] wa, ra;

  initial begin
    $display("--------------------------------------------------------------");
    $display(" bram_deep_buffer: %0d x %0d, %0d banks, read latency %0d",
             DEPTH, DW, NB, dut.LATENCY);
    $display("--------------------------------------------------------------");
    repeat (4) @(negedge clk);

    // 1. First and last word of every bank
    for (b = 0; b < NB; b = b + 1) begin
      cycle(1, (b << BANK_AW),                      32'hA000_0000 | b, 0, 0);
      cycle(1, (b << BANK_AW) | ((1<<BANK_AW) - 1), 32'hB000_0000 | b, 0, 0);
    end
    for (b = 0; b < NB; b = b + 1) begin
      cycle(0, 0, 0, 1, (b << BANK_AW));
      cycle(0, 0, 0, 1, (b << BANK_AW) | ((1<<BANK_AW) - 1));
    end
    $display("Phase 1 (every bank) issued %0d reads", wp);

    // 2. Write, then read the same address on the next cycle
    for (i = 0; i < 200; i = i + 1) begin
      wa = $random;
      cycle(1, wa, $random, 0, 0);
      cycle(0, 0, 0, 1, wa);
    end
    $display("Phase 2 (write then read next cycle) done");

    // 3. Random traffic. A read and a write to the same address in the same
    //    cycle is a collision, so the testbench never issues one.
    for (i = 0; i < 20000; i = i + 1) begin
      wa = $random;
      ra = (($random & 1) != 0) ? wa ^ 1 : $random;   // often hit the same bank
      if (ra == wa) ra = ra ^ 1;
      cycle(($random & 1), wa, $random, (($random & 3) != 0), ra);
    end

    cycle(0, 0, 0, 0, 0);
    repeat (dut.LATENCY + 4) @(negedge clk);

    $display("--------------------------------------------------------------");
    $display(" reads issued %0d, reads checked %0d, errors %0d", wp, rp, errors);
    test_passed = (errors == 0) && (rp == wp);
    if (test_passed) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $display("--------------------------------------------------------------");
    $finish;
  end

endmodule
