#!/usr/bin/env bash
# Build and run the quantizer equivalence bench (issue #186): the pipelined
# jc_quant against the combinational jc_quant_core over a bounded sweep.
# Exit 0 only on "RESULT: PASS". With --negative, corrupts one expected
# value (INJECT_BUG) and exits 0 only if the bench reports FAIL (a build
# error does not count).
set -u
cd "$(dirname "$0")/../.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
def=()
[ "${1:-}" = "--negative" ] && def=(-DINJECT_BUG=1)
iverilog -g2005 "${def[@]}" -o "$out/sim" \
    rtl/jc_quant.v rtl/jc_quant_core.v rtl/jc_quant_recip.v rtl/jc_quant_rom_rows.v \
    rtl/jc_quant_mul.v rtl/jc_quant_sum_windows.v rtl/jc_quant_clamp.v \
    verification/rtl/tb_quantizer_equiv.v || exit 2
start=$(date +%s)
log=$(vvp "$out/sim")
echo "$log"
echo "runtime: $(( $(date +%s) - start )) s"
if [ "${1:-}" = "--negative" ]; then
    echo "$log" | grep -q "RESULT: FAIL"
else
    echo "$log" | grep -q "RESULT: PASS"
fi
