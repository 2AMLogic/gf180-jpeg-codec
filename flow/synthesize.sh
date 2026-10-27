#!/usr/bin/env bash
# Regenerate the committed gate-level netlist of jpeg_codec_top from the RTL
# (T1 item 1). Runs `klt synthesize synthesize.json`, which claims flow/netlist/
# as its run directory (it must not exist, so the old one is removed first),
# then makes the report and scripts repo-relative so nothing host-specific is
# committed. Yosys *.log files stay untracked (see .gitignore).
#
#   flow/synthesize.sh           regenerate flow/netlist/ and flow/netlist/report.json
#   flow/synthesize.sh --check   cheap freshness check: exit 0 iff the committed
#                                report still matches the RTL and library hashes
#                                (what manifests/attest/item1.inventory.json runs)
#
# Needs klt, yosys and the pinned PDK (see pdk.env).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=pdk.env
. ./pdk.env

KLT="${KLT:-klt}"

if [ "${1:-}" = "--check" ]; then
  exec "$KLT" synthesize synthesize.json --check netlist/report.json
fi

rm -rf netlist
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
"$KLT" synthesize synthesize.json --format json > "$tmp"
mv "$tmp" netlist/report.json
ROOT=$(git rev-parse --show-toplevel)
sed -i "s#$ROOT/#./#g; s#$HOME#~#g" netlist/*.ys netlist/*.json
echo "netlist in flow/netlist/jpeg_codec_top_synth.v"
