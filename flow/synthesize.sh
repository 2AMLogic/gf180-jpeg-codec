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
# Dispatch hosts: run with TMPDIR=/tmp (a deep ambient TMPDIR can stall this run until the watchdog fires, rc=124) -- see README.md "TMPDIR on dispatch hosts" (klayout-tools#6076).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=pdk.env
. ./pdk.env

KLT="${KLT:-klt}"
# klt-watchdog.sh bounds every "$KLT" call below (issue #156): KLT_TIMEOUT
# seconds, default 900; on expiry it captures diagnostics, kills the run's
# process group and returns 124, which this script then exits with.
# shellcheck source=klt-watchdog.sh
. ./klt-watchdog.sh

if [ "${1:-}" = "--check" ]; then
  rc=0
  # Bounded too (issue #156): --check also runs the synthesis engine, and
  # exec would replace this wrapper, leaving nothing to time it out. The
  # leading "-" arguments pass klt's stdout/stderr straight through, and
  # klt's own exit status is propagated unchanged.
  klt_bounded - - "klt-watchdog-check-$$.diag.txt" \
    "$KLT" synthesize synthesize.json --check netlist/report.json || rc=$?
  exit "$rc"
fi

rm -rf netlist
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
# On expiry klt_bounded returns 124 and this script exits with it (set -e);
# on engine failure its status propagates the same way the direct call's did.
klt_bounded "$tmp" - "klt-watchdog-$$.diag.txt" \
  "$KLT" synthesize synthesize.json --format json
mv "$tmp" netlist/report.json
ROOT=$(git rev-parse --show-toplevel)
sed -i "s#$ROOT/#./#g; s#$HOME#~#g" netlist/*.ys netlist/*.json
echo "netlist in flow/netlist/jpeg_codec_top_synth.v"
