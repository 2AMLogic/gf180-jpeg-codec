#!/usr/bin/env bash
# Negative control for the top-level golden suite (issue #88). The mutant
# negctl/jc_bitpack_nostuff.v is rtl/jc_bitpack.v with 0xFF byte stuffing
# disabled (line 55 only); the suite must exit exactly 3, klt's
# "ran, a test failed" status (0 = all passed, 1 = request/environment error,
# so 1 here would mean it did not run). Any other status fails this script. Needs klt pinned at 0.8.0 with the
# functional-verification extra (cocotb) and iverilog on PATH.
set -uo pipefail
cd "$(dirname "$0")"
want="$(sed "55s/.*/  wire        n_ff      = 1'b0;/" ../../rtl/jc_bitpack.v)"
if [ "$want" != "$(cat negctl/jc_bitpack_nostuff.v)" ]; then
  echo "FAIL: negctl/jc_bitpack_nostuff.v is not rtl/jc_bitpack.v with line 55 mutated" >&2
  exit 1
fi
outdir="${1:-$(mktemp -d)}"
uvx --from "klayout-tools[functional-verification]==0.8.0" klt functional-verification \
  top_golden.negative_control.request.json -o "$outdir" --format json > "$outdir/report.json"
rc=$?
if [ "$rc" -eq 3 ]; then echo "negative control exit $rc (ok); report: $outdir/report.json"
else echo "FAIL: negative control exited $rc, expected 3" >&2; exit 1; fi
