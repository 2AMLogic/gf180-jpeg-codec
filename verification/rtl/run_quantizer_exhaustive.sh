#!/usr/bin/env bash
# Build and run the exhaustive quantizer bench (issue #44). Exit 0 only on
# "RESULT: PASS". With --negative, injects a reference bug and exits 0 only if
# the bench reports FAIL (a build error does not count).
set -u
cd "$(dirname "$0")/../.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
def=()
[ "${1:-}" = "--negative" ] && def=(-DINJECT_BUG=1)
iverilog -g2005 "${def[@]}" -o "$out/sim" rtl/jc_quant_core.v verification/rtl/tb_quantizer_exhaustive.v || exit 2
start=$(date +%s)
log=$(vvp "$out/sim")
echo "$log"
echo "runtime: $(( $(date +%s) - start )) s"
if [ "${1:-}" = "--negative" ]; then
    echo "$log" | grep -q "RESULT: FAIL"
else
    echo "$log" | grep -q "RESULT: PASS"
fi
