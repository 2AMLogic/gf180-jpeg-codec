#!/usr/bin/env bash
# Cold-start smoke flow: synthesize -> place-and-route -> drc -> extract -> lvs -> sta
# on the pinned PDK, with one report per stage under records/<timestamp>-<sha>/.
# A failing stage is recorded as it ran and the script carries on; it exits
# non-zero if any stage failed. Nothing here is evidence about the codec.
#
#   flow/smoke/run.sh        (from anywhere; needs klt, yosys, openroad, klayout)
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck source=../pdk.env
. ../pdk.env || exit 2

KLT="${KLT:-klt}"
# klt-watchdog.sh bounds every stage (issue #156) -- all six are "$KLT" calls
# funnelled through stage(). A stage that exceeds KLT_TIMEOUT (default 900 s)
# is recorded with rc=124 and the flow carries on, matching this script's
# record-failures-and-continue contract.
# shellcheck source=../klt-watchdog.sh
. ../klt-watchdog.sh
TOP=smoke_counter
LIB=gf180mcu_fd_sc_mcu9t5v0
SHA=$(git rev-parse --short HEAD)
REC="records/$(date -u +%Y%m%dT%H%M%SZ)-$SHA"
mkdir -p "$REC"
rc=0

stage() {  # stage <name> <command...>; the JSON report is stdout, stderr kept beside it
  local name="$1" s=0
  shift
  echo "=== $name"
  klt_bounded "$REC/$name.json" "$REC/$name.stderr" "$REC/$name.watchdog.diag.txt" \
    "$@" || s=$?
  if [ "$s" -ne 0 ]; then
    echo "--- $name FAILED (rc=$s)" >&2
    rc=1
  fi
}

stage synthesize "$KLT" synthesize synthesize.json --format json
# synthesize writes the netlist under a per-run directory; place-and-route.json
# names a stable path, so copy the newest one there.
mkdir -p .klt/synthesize
cp "$(ls -t .klt/synthesize/run-*/${TOP}_synth.v | head -1)" ".klt/synthesize/${TOP}_synth.v"
stage place-and-route "$KLT" place-and-route place-and-route.json --format json
GDS=".klt/place-and-route/$TOP.gds"
stage drc "$KLT" drc "$GDS" --deck gf180mcu --top "$TOP" --format json
stage extract "$KLT" extract "$GDS" --deck gf180mcu --abstract-cells "${LIB}__*" \
  --def-net-names -o "$TOP.gate.spice" --format json
stage lvs "$KLT" lvs lvs.json --format json
stage sta "$KLT" sta sta.json --format json

{
  echo "klt:      $("$KLT" --version)"
  echo "yosys:    $(yosys -V)"
  echo "openroad: $(openroad -version 2>&1 | head -1)"
  echo "pdk:      $PDK, open_pdks $OPEN_PDKS_REV (ciel $CIEL_VERSION)"
  echo "git:      $(git rev-parse HEAD)"
} > "$REC/versions.txt"

# Reports carry absolute host paths; make them repo-relative before they are committed.
ROOT=$(git rev-parse --show-toplevel)
sed -i "s#$ROOT/#./#g; s#$HOME#~#g" "$REC"/*.json "$REC"/*.stderr
echo "records in flow/smoke/$REC"
exit $rc
