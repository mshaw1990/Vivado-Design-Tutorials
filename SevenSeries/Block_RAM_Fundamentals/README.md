# 7 Series Block RAM Fundamentals

***Target part: xc7v2000tflg1925-2 (Virtex-7 2000T, -2 speed grade)***

This tutorial is a hands-on look at 7 Series block RAM (RAMB18E1 / RAMB36E1). You will:

1. Instantiate a **RAMB18E1 primitive** and write the **same RAM as inferable RTL**, then prove in simulation that they behave the same.
2. See the three **write modes** (`WRITE_FIRST`, `READ_FIRST`, `NO_CHANGE`), **read latency 1 vs 2** (`DO_REG`), and **output reset to `SRVAL`**.
3. Measure the **Fmax gain from the BRAM output register** with an out-of-context (OOC) run.
4. Build a **deep, pipelined, multi-bank buffer** and look at how it is placed across the **SLRs** of the XC7V2000T.

> **Verification status:** both testbenches pass in Icarus Verilog 12, using the RAMB18E1 and glbl models from AMD's open-source [UNISIM library](https://github.com/Xilinx/XilinxUnisimLibrary). The deep buffer also passes with `AW` = 11, 13 and 17 and with `GROUP` values that do not divide the bank count. The Vivado scripts (`run_sim.tcl`, `run_xsim.sh`), synthesis, OOC implementation and SLR pblock steps **have not been run in Vivado yet**, so the timing and utilization results are yours to discover.

## Requirements

- Vivado (any recent release with 7 Series support). The XC7V2000T needs a **paid Vivado license**. It is not supported by the free Standard edition.
- Simulations run either inside Vivado with `scripts/run_sim.tcl` (any OS), or from a Linux shell with `sim/run_xsim.sh`.

## Directory structure

```
Block_RAM_Fundamentals/
├── hdl/
│   ├── bram_tdp_prim.v       1K x 18 TDP RAM: RAMB18E1 instantiation
│   ├── bram_tdp_infer.v      1K x 18 TDP RAM: inferred RTL, same behavior
│   ├── bram_fmax_harness.v   Registered wrapper for timing the TDP RAM
│   ├── bram_sdp_bank.v       1K x 32 SDP bank (inference template, latency 2)
│   └── bram_deep_buffer.v    64K x 32 buffer: 64 banks, pipelined fan-out and read mux
├── sim/
│   ├── tb_bram_tdp.v         Primitive vs inferred, all write modes, DO_REG 0/1
│   ├── tb_bram_deep_buffer.v Self-checking scoreboard test of the deep buffer
│   └── run_xsim.sh           Command-line simulation of both testbenches
└── scripts/
    ├── create_project.tcl    Project-mode setup for GUI use
    ├── run_sim.tcl           Source in Vivado to run both testbenches
    └── run_ooc.tcl           OOC synth + implementation with summary reports
```

---

## Running the simulations

**Inside Vivado (any OS).** In the Tcl console, enter:

```tcl
source <path>/SevenSeries/Block_RAM_Fundamentals/scripts/run_sim.tcl
```

The script does the following:
- creates (or reopens) `vivado_project/`
- runs `tb_bram_tdp`, then `tb_bram_deep_buffer`
- prints a PASSED/FAILED summary
- in the GUI, leaves the last simulation open with its waveform window.

To rerun one testbench and keep it open for waveforms:

```tcl
bram_sim tb_bram_tdp
```

You can also run it in batch mode: `vivado -mode batch -source scripts/run_sim.tcl`.

**On Windows,** paths inside the generated simulation directories can exceed the 260-character limit. If your checkout is deep, put the project somewhere short before sourcing the script:

```tcl
set ::bram_project_dir D:/vp
source <path>/SevenSeries/Block_RAM_Fundamentals/scripts/run_sim.tcl
```

**From a Linux shell:**

```bash
source <Vivado install>/settings64.sh
cd SevenSeries/Block_RAM_Fundamentals/sim
./run_xsim.sh                    # both testbenches, or name one
```

## Lab 1: Primitive vs inferred, write modes and latency

Run `bram_sim tb_bram_tdp` in Vivado, or `./run_xsim.sh tb_bram_tdp` from a shell.

The testbench instantiates six configurations, `{WRITE_FIRST, READ_FIRST, NO_CHANGE} x {DO_REG=0, DO_REG=1}`. Each configuration contains both the primitive and the inferred RAM.

**Directed phase:**

| Step | Port A operation | Expected output |
|---|---|---|
| 1 | write `mem[5] = 0x11` | — |
| 2 | write `mem[6] = 0x22` | — |
| 3 | read `mem[5]` | `0x11` (all modes) |
| 4 | read `mem[6]` | `0x22` (all modes) |
| 5 | **write `mem[5] = 0x55`** (read-during-write) | `WRITE_FIRST`: `0x55`, `READ_FIRST`: `0x11`, `NO_CHANGE`: `0x22` |
| 6 | reset (EN=1, WE=0) | `SRVAL = 0x2BEEF` one cycle later |
| 7 | port B reads `mem[5]` | `0x55` |

The messages from the six configurations are interleaved in the log, because each one reports at its own latency. Each check appears **1 cycle** after the operation when `DO_REG=0`, and **2 cycles** after when `DO_REG=1`. Open the waveform (`bram_sim tb_bram_tdp` in the Vivado GUI) and look at `u_rf_r0` next to `u_rf_r1` to see the extra cycle.

**Random phase:** 5000 cycles of random traffic. Port A uses addresses 0–511 and port B uses 512–1023, so they never collide. The primitive and inferred outputs are compared on every cycle. The run ends with `TEST PASSED` or `TEST FAILED`.

Things to look for in the code:

- `bram_tdp_prim.v`: the address is `{addr, 4'b0000}`, because in x18 mode only `ADDR[13:4]` is used. The 18-bit word is split into `DIADI[15:0]` plus `DIPADIP[1:0]`.
- `bram_tdp_prim.v`: reset goes to `RSTRAM` when `DO_REG=0` and to `RSTREG` when `DO_REG=1`.
- `bram_tdp_infer.v`: the write mode comes **only from how the read is coded** relative to the write.
- **GSR:** `glbl.v` holds GSR for 100 ns, so the testbench waits 200 ns before it checks anything. Forgetting `glbl` is the most common reason a primitive simulation shows all X.

**Exercise:** change `SRVAL` in the testbench, or assert `rst_a` while `en_a = 0` with `DO_REG = 0`. Check UG473 for what `RSTRAM` should do when EN is low, and compare it with the primitive model.

## Lab 2: Fmax with and without the output register

From the `Block_RAM_Fundamentals` directory:

```bash
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_fmax_harness 2.0 none DO_REG=0
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_fmax_harness 2.0 none DO_REG=1
```

`bram_fmax_harness` registers every input and adds the two read ports into a register. That creates a real **BRAM -> adder -> flip-flop** path. The target period is 2.0 ns (500 MHz).

Compare the `summary.txt` files under `ooc_runs/`:

- **`DO_REG=0`:** the critical path starts at the BRAM clock-to-out time of the output latch, which is slow. Expect negative slack at 500 MHz.
- **`DO_REG=1`:** the path starts at the BRAM output register, which is much faster. The Fmax should now be limited by the adder and routing, or by the BRAM minimum period (`post_route_pulse_width.rpt`).

**Things to check:**

1. Open `post_synth_util.rpt` and confirm you got **one RAMB18E1** and no LUTRAM.
2. In the Vivado log, find the **"Block RAM: Preliminary Mapping Report"**. It lists the inferred RAM's mode, widths and whether the output register (`OUT_REG`) was absorbed.
3. Repeat with `USE_PRIM=1` and confirm the results match the inferred version.

## Lab 3: Deep buffer simulation

Run `bram_sim tb_bram_deep_buffer` in Vivado, or `./run_xsim.sh tb_bram_deep_buffer` from a shell.

`bram_deep_buffer` is a 64K x 32 simple dual-port buffer built from 64 banks of 1K x 32. A reported read latency of **8** is expected:

| Stage | What happens |
|---|---|
| A | Input registers |
| B | Address/data/enable registers, **one copy per 8 banks** (`GROUP`), kept separate with `DONT_TOUCH` |
| C | BRAM output latch. **Only the addressed bank is enabled**, which saves power. |
| D | BRAM output register (`DOB_REG`) |
| E | Zero every bank's output except the one that was read |
| F | Radix-4 OR tree, one register per level (3 levels for 64 banks) |

The testbench:
- writes and reads the first and last word of every bank
- tests write-then-read-next-cycle
- runs 20,000 random cycles against a scoreboard.

It never reads and writes the **same address in the same cycle**, because that is a BRAM collision.

**Exercise:** stage E exists because banks that were not read still hold stale data in their output registers. The 7 Series output register has its own synchronous reset (`RSTREG`). Rewrite `bram_sdp_bank` so the bank resets its own output register when it was not read. That moves stage E into the BRAM and saves a pipeline stage and the AND gates.

## Lab 4: Deep buffer on an SSI device

The XC7V2000T is made of **four SLRs**. It has 1,292 RAMB36 in total, about 323 per SLR.

```bash
# 64 banks (about 64 RAMB36), placed freely
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_deep_buffer 2.0 none
# Same design, locked into SLR1 with a pblock
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_deep_buffer 2.0 SLR1
# 256 banks (256K x 32): about 80% of one SLR's BRAM
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_deep_buffer 2.0 none AW=18
# 512 banks: more than one SLR holds, so the design must cross SLRs
vivado -mode batch -source scripts/run_ooc.tcl -tclargs bram_deep_buffer 2.0 none AW=19
```

For each run, `summary.txt` gives the number of BRAMs in each SLR, the setup WNS and an estimated Fmax. `post_route_util.rpt` also has the per-SLR utilization table.

**Questions to investigate:**

1. With `AW=19`, which paths fail? Open `post_route.dcp` and run `report_timing -max_paths 20`. Look for paths that cross SLRs on Super Long Lines (SLLs).
2. Change `GROUP` (for example `GROUP=64` for a single copy of the register, or `GROUP=4`) and watch how the fan-out of the stage-B registers changes timing.
3. Try `AW=19 GROUP=4`. Does the extra register duplication help once the design spans SLRs? What would you add, such as registers on each side of the SLR crossing or per-SLR sub-buffers, to get back to 500 MHz?
4. With `SLR1`, does timing improve compared to free placement for `AW=16`?

> If the `SLR1` pblock step fails, your Vivado release may not accept `get_clock_regions -of_objects [get_slrs ...]`. Replace the computed range in `run_ooc.tcl` with the clock-region range of the SLR, which you can read from the Device view.

## Lab 0 (optional): GUI project

```bash
vivado -source scripts/create_project.tcl
```

This creates `vivado_project/` with all sources. `tb_bram_tdp` is set as the simulation top. Run **Flow Navigator > Run Simulation** to get waveforms. `scripts/run_sim.tcl` creates this project automatically if it does not exist.

## References

- **UG473:** 7 Series FPGAs Memory Resources. Covers BRAM and FIFO architecture, write modes, collision rules and ECC.
- **UG953:** Vivado Design Suite 7 Series FPGA Libraries Guide. Lists RAMB18E1/RAMB36E1 ports and attributes.
- **UG901:** Vivado Design Suite User Guide: Synthesis. Covers RAM inference templates and `ram_style`.
- **DS183:** Virtex-7 T and XT FPGAs Data Sheet. Gives BRAM switching characteristics and Fmax.
- **UG872:** Large FPGA Methodology Guide. Covers design for SSI devices.
