#!/usr/bin/env bash
#------------------------------------------------------------------------------
# Run both testbenches in the Vivado simulator (xsim) from the command line.
#
#   source <Vivado install>/settings64.sh
#   ./run_xsim.sh                 # run both testbenches
#   ./run_xsim.sh tb_bram_tdp     # run one
#
# Waveforms: add "--gui" to the xsim line, or use scripts/create_project.tcl.
#------------------------------------------------------------------------------
set -euo pipefail

: "${XILINX_VIVADO:?Source the Vivado settings64.sh script first}"

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDL_DIR="${SIM_DIR}/../hdl"
BUILD_DIR="${SIM_DIR}/build"

TESTS=("$@")
if [ ${#TESTS[@]} -eq 0 ]; then
  TESTS=(tb_bram_tdp tb_bram_deep_buffer)
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# glbl.v models the global set/reset (GSR) that the UNISIM primitives need.
xvlog "${HDL_DIR}"/*.v \
      "${SIM_DIR}/tb_bram_tdp.v" \
      "${SIM_DIR}/tb_bram_deep_buffer.v" \
      "${XILINX_VIVADO}/data/verilog/src/glbl.v"

status=0
for tb in "${TESTS[@]}"; do
  xelab -debug typical -L unisims_ver "${tb}" glbl -s "${tb}_snap"
  xsim "${tb}_snap" -R | tee "${tb}.log"
  if grep -q "TEST PASSED" "${tb}.log"; then
    echo ">>> ${tb}: PASSED"
  else
    echo ">>> ${tb}: FAILED (see ${BUILD_DIR}/${tb}.log)"
    status=1
  fi
done

exit ${status}
