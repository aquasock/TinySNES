#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Simulate the TINYSNES_FETCH_PROBE sampler found in fpga/snes/src/snestang_top.v.
#
#   tools/tests/fetch_probe_tb.sh
#
# The bench needs the sampler text, so it is extracted from the shipping source
# into a temporary file rather than retyped: a copy would drift, and this
# instrument has already reported a false result once when it measured the wrong
# instant.  The stimulus puts a different value on ROM_Q every master clock, so
# each captured field's provenance is provable rather than assumed.
#
# Requires iverilog.  Exit status is the bench's: 0 when every field matches.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src/snestang_top.v"
tb="$root/tools/tests/fetch_probe_tb.sv"

command -v iverilog >/dev/null || { echo "iverilog is required" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The first `ifdef TINYSNES_FETCH_PROBE in the file is the sampler; it holds no
# nested conditionals, so the first matching `endif closes it.
awk '/^`ifdef TINYSNES_FETCH_PROBE$/{f=1} f{print} f&&/^`endif$/{exit}' "$src" > "$tmp/sampler.v"
[[ -s "$tmp/sampler.v" ]] || { echo "no sampler block found in $src" >&2; exit 1; }
grep -q 'fp_bus' "$tmp/sampler.v" || { echo "extracted block is not the fetch sampler" >&2; exit 1; }

iverilog -g2012 -DTINYSNES_FETCH_PROBE -I "$tmp" -o "$tmp/tb.vvp" "$tb"
"$tmp/tb.vvp"
