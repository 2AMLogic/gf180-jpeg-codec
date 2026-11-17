#!/usr/bin/env bash
# Synthesis-only size estimate of decision record 0004's option C: the three
# gf180_sram_256x32 memories implemented in standard cells instead of left as
# black boxes (issue #115). The request is derived from synthesize.json at run
# time into synthesize-optc.request.json (gitignored) with exactly two fields
# overridden -- sram_blackbox.v becomes sram_stdcell.v, and outputs.dir becomes
# netlist-optc -- so the figures are comparable with the committed black-box
# baseline in netlist/report.json and the derived request cannot drift the way
# a hand-maintained copy did (issue #183).
#
#   flow/synthesize-optc.sh      write flow/netlist-optc/ and print the headline
#                                numbers beside the committed baseline
#
# This is an estimate, not tracked evidence: there is deliberately no --check
# mode. The committed baseline's `flow/synthesize.sh --check` is the only
# freshness contract in this directory, and this run does not touch it.
# flow/netlist-optc/ is gitignored -- the generated netlist is ~8 MB and is
# reproducible from synthesize.json via the derivation below. Copy report.json
# and run.stderr into
# a new flow/records/<timestamp>Z-<short sha>/ directory to record a run
# (records are append-only; never overwrite an existing one).
#
# Needs klt, yosys and the pinned PDK (see pdk.env). One local Yosys job, not
# a grid; it ran in well under a minute and under 1 GB when recorded.
# Dispatch hosts: run with TMPDIR=/tmp (a deep ambient TMPDIR can stall this run until the watchdog fires, rc=124) -- see README.md "TMPDIR on dispatch hosts" (klayout-tools#6076).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=pdk.env
. ./pdk.env

KLT="${KLT:-klt}"
# klt-watchdog.sh bounds the timed run below (issue #156): KLT_TIMEOUT
# seconds, default 900; the watchdog wraps /usr/bin/time -v itself, so the
# whole group (time -> klt -> yosys -> abc) is what gets killed on expiry.
# shellcheck source=klt-watchdog.sh
. ./klt-watchdog.sh

rm -rf netlist-optc
tmp=$(mktemp)
err=$(mktemp)
trap 'rm -f "$tmp" "$err"' EXIT

# The option-C request is derived, not committed (issue #183): a hand-maintained
# copy of synthesize.json drifted as soon as the quantizer split added sources.
# Writing it into this directory keeps every other field inherited verbatim and
# the relative source paths resolving exactly as synthesize.json's own do. The
# guard makes a future rename of sram_blackbox.v in synthesize.json fail loudly
# here instead of silently synthesizing the committed baseline under the
# option-C banner.
python3 - <<'PYEOF'
import json

req = json.load(open('synthesize.json'))
if 'sram_blackbox.v' not in req['sources']:
    raise SystemExit(
        'synthesize.json no longer lists sram_blackbox.v; the option-C '
        'derivation in synthesize-optc.sh has nothing to swap -- update it')
req['sources'] = ['sram_stdcell.v' if s == 'sram_blackbox.v' else s
                  for s in req['sources']]
req['outputs']['dir'] = 'netlist-optc'
with open('synthesize-optc.request.json', 'w') as fh:
    json.dump(req, fh, indent=2)
    fh.write('\n')
PYEOF

# /usr/bin/time -v supplies the wall clock and peak RSS the record quotes; klt's
# own stderr lands in the same file so a failure is recorded as it ran. Bounded
# by the watchdog (issue #156): on expiry it returns 124, the failure path below
# records it and exits non-zero, and the diagnostic names every process the
# group kill took down.
if ! klt_bounded "$tmp" "$err" "klt-watchdog-optc-$$.diag.txt" \
        /usr/bin/time -v "$KLT" synthesize synthesize-optc.request.json \
        --format json; then
    mkdir -p netlist-optc
    cp "$err" netlist-optc/run.stderr
    cp "$tmp" netlist-optc/report.json
    echo "klt synthesize failed; stderr in flow/netlist-optc/run.stderr" >&2
    tail -40 "$err" >&2
    exit 1
fi

mv "$tmp" netlist-optc/report.json
cp "$err" netlist-optc/run.stderr
ROOT=$(git rev-parse --show-toplevel)
sed -i "s#$ROOT/#./#g; s#$HOME#~#g" netlist-optc/*.ys netlist-optc/*.json \
    netlist-optc/run.stderr

echo "netlist in flow/netlist-optc/jpeg_codec_top_synth.v (gitignored, ~8 MB)"
echo

python3 - <<'PYEOF'
import json

base = json.load(open('netlist/report.json'))
optc = json.load(open('netlist-optc/report.json'))

print('%-22s %18s %18s %18s' % ('field', 'baseline (bbox)', 'option C', 'delta'))
for k in ('instance_count', 'area_um2', 'sequential_area_um2'):
    print('%-22s %18s %18s %+18s' % (k, base[k], optc[k],
                                     round(optc[k] - base[k], 4)))
print()
print('status:                      ', optc['status'])
print('blackbox_modules:            ', optc['blackbox_modules'])
print('macro still an instance type:',
      'gf180_sram_256x32' in optc['instance_counts_by_type'])
print('critical_path_ps:            ', optc['timing']['critical_path_ps'],
      '(target', optc['timing']['delay_target_ps'], 'ps)')
for m in optc['memory_mapping']['modules']:
    if m['module'] == 'gf180_sram_256x32':
        print('memory_mapping:              ', json.dumps(m, sort_keys=True))
print('klt_version:                 ', optc['provenance']['klt_version'])
print('engine_version:              ', optc['engine_version'])
print('pdk:                         ', optc['provenance']['pdk']['version'])
print('input.content_hash:          ',
      optc['provenance']['input']['content_hash'])
PYEOF

grep -E 'Elapsed \(wall clock\)|Maximum resident set size' netlist-optc/run.stderr || true
