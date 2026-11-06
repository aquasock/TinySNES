#!/usr/bin/env bash
# Gate: the board-level bench still elaborates.
#
# `tools/sim/run_board_sim.sh` is the only simulation in this tree that
# instantiates snestang_top against the real SDRAM controller and a modelled
# SDRAM part, so it is the one bench that can see a fault in the board's own
# memory path.  It stopped compiling in the Mode 7 widening of core-log entry
# 16 and nobody noticed for several cycles, because nothing else in the project
# ever invoked it (entry 23).  This is the something else.
#
# It is deliberately a lint rather than a full build-and-run: `--lint` shares
# the file list with the bench itself, so the two cannot drift, and it takes
# under a second instead of the forty a Verilator build costs.  What it catches
# is anything that makes the sources unelaboratable, which is exactly the class
# of defect that rotted the bench: `ppu.v` carried `27'h7FFFFFC0`, a 31-bit
# literal at a 27-bit width, which Verilator rejects outright and yosys
# silently truncates.  That asymmetry is why the bitstream stayed correct while
# the bench was dead, and why a yosys- or slang-based check would not have
# caught it -- only Verilator refuses the literal.
#
# This does not run the bench and so cannot tell you the machine boots; it
# answers the narrower question of whether the bench is still a bench.
#
#   tools/tests/check_board_sim_lint.sh
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== board bench elaboration ==="
if ! "$root/tools/sim/run_board_sim.sh" --lint; then
    echo "board sim: FAIL -- the board-level bench no longer elaborates." >&2
    echo "  This is the only bench that models the board's SDRAM path; fix it" >&2
    echo "  before trusting any memory-path result from simulation." >&2
    exit 1
fi
echo "board sim: OK"
