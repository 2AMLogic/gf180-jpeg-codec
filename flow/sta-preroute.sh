#!/usr/bin/env bash
# Pre-route timing of the committed netlist at the five spec §10 Liberty views.
#
# `klt sta` verilog-mode (DEF-free, `geometry_source: "netlist_estimate"`) over
# flow/netlist/jpeg_codec_top_synth.v, one request per macro-free top-level
# child of jpeg_codec_top, each characterizing all five views in a single
# round trip via `pdk.corners`. Cell delays only: the library declares no
# wire-load model, so no wire parasitics of any kind are included.
#
# `jpeg_codec_top` itself CANNOT be timed. link_design resolves netlist
# instances against loaded LEF masters and no LEF exists for the three
# gf180_sram_256x32 instances (issue #31), so the top dies on ORD-2013. This
# run records that failure as a negative control; jc_sram_wrap and everything
# reached through it is therefore ABSENT from the numbers, not merely untimed.
#
# This is NOT signoff evidence and NOT T1 item 5 evidence (#34 owns that,
# post-route with SPEF). Records are append-only: each run writes a new
# directory and never edits an old one.
#
#   flow/sta-preroute.sh                    run every module into a new record dir
#   flow/sta-preroute.sh --out DIR          write into DIR instead
#   flow/sta-preroute.sh --only jc_dct      run one module by name (repeatable)
#   flow/sta-preroute.sh --list-check       print the children derived from the netlist
#   flow/sta-preroute.sh --update-modules   rewrite sta-preroute.modules from the netlist
#
# Needs klt, openroad, jq, python3 and the pinned PDK (see pdk.env). Each
# module is one local OpenROAD job; they run sequentially, never fanned out.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
# shellcheck source=pdk.env
. ./pdk.env || exit 2

KLT="${KLT:-klt}"
BASE=sta-preroute.json
MODULE_LIST=sta-preroute.modules
TOP=jpeg_codec_top

REC=""
list_check=""
update_modules=""
ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) REC="$2"; shift 2 ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --list-check) list_check=1; shift ;;
    --update-modules) update_modules=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

NETLIST=$(jq -r .verilog "$BASE")
[ -f "$NETLIST" ] || { echo "no netlist at flow/$NETLIST" >&2; exit 2; }

# Derive the macro-free children of $TOP from the netlist itself rather than
# trusting a hand-written list: every module type instantiated by $TOP that is
# also defined in the netlist, minus any whose subtree reaches the macro.
# Emits TAB-separated "FREE|MACRO <slug> <verilog module name>"; the slug is a
# filesystem-safe basename, because Yosys emits parameterized modules as
# escaped identifiers full of $, \, = and '.
derive_children() {
  python3 -I - "$NETLIST" "$TOP" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split('\n')
top = sys.argv[2]
order = []
for i, l in enumerate(src):
    m = re.match(r'^module\s+([^\s(]+)', l)
    if m:
        order.append((m.group(1), i))
bounds = {}
for n, (name, s) in enumerate(order):
    bounds[name] = (s, order[n + 1][1] if n + 1 < len(order) else len(src))
defined = set(bounds)
NOT_INSTANCES = {'wire', 'input', 'output', 'inout', 'assign', 'reg', 'parameter', 'localparam'}

def instantiated(mod):
    s, e = bounds[mod]
    out = set()
    for l in src[s:e]:
        m = re.match(r'^  (\S+)\s', l)
        if m and m.group(1) not in NOT_INSTANCES:
            out.add(m.group(1).lstrip('\\') if m.group(1).startswith('\\') else m.group(1))
    return out

def reaches_macro(mod, seen=None):
    seen = set() if seen is None else seen
    if mod in seen:
        return False
    seen.add(mod)
    for c in instantiated(mod):
        if c == 'gf180_sram_256x32':
            return True
        key = c if c in defined else '\\' + c
        if key in defined and reaches_macro(key, seen):
            return True
    return False

def slug(name):
    # Exact, not shortened: a Yosys parameterized name differs from its
    # siblings only in the parameter value, so nothing may be collapsed.
    return re.sub(r'[^A-Za-z0-9]+', '_', name.lstrip('\\')).strip('_')

for c in sorted(instantiated(top)):
    key = c if c in defined else '\\' + c
    if key not in defined:
        continue
    print('%s\t%s\t%s' % ('MACRO' if reaches_macro(key) else 'FREE', slug(c), c))
PY
}

if [ -n "$list_check" ]; then
  echo "# children of $TOP defined in flow/$NETLIST:"
  derive_children
  exit 0
fi

derived=$(derive_children) || exit 2
free_now=$(printf '%s\n' "$derived" | awk -F'\t' '$1 == "FREE" { print $2 "\t" $3 }')

if [ -n "$update_modules" ]; then
  {
    echo "# Macro-free top-level children of $TOP, derived from the committed"
    echo "# netlist by flow/sta-preroute.sh --update-modules. TAB-separated:"
    echo "#   <filesystem-safe slug><TAB><verilog module name>"
    echo "# Every other child of $TOP is jc_sram_wrap, which carries the"
    echo "# gf180_sram_256x32 macro and cannot be linked without its LEF (#31)."
    printf '%s\n' "$free_now"
  } > "$MODULE_LIST"
  echo "wrote flow/$MODULE_LIST"
  exit 0
fi

[ -f "$MODULE_LIST" ] || { echo "missing flow/$MODULE_LIST (run --update-modules)" >&2; exit 2; }
if ! diff -u <(grep -v '^#' "$MODULE_LIST") <(printf '%s\n' "$free_now") > /dev/null; then
  echo "flow/$MODULE_LIST is stale against flow/$NETLIST:" >&2
  diff -u <(grep -v '^#' "$MODULE_LIST") <(printf '%s\n' "$free_now") >&2
  echo "re-run with --update-modules and re-read the record's scope notes" >&2
  exit 2
fi

if [ ${#ONLY[@]} -gt 0 ]; then
  selected=""
  for want in "${ONLY[@]}"; do
    hit=$(printf '%s\n' "$free_now" | awk -F'\t' -v w="$want" '$1 == w || $2 == w')
    [ -n "$hit" ] || { echo "--only $want is not a macro-free child of $TOP" >&2; exit 2; }
    selected="${selected}${hit}"$'\n'
  done
  free_now=$(printf '%s' "$selected")
fi

if [ -z "$REC" ]; then
  REC="records/$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
fi
mkdir -p "$REC"
rc=0

tmp=.sta-preroute-run.json     # must live in flow/ so the request's relative
trap 'rm -f "$tmp"' EXIT       # paths resolve exactly as the committed base's do

run_one() {  # run_one <hdl_toplevel> <output basename>
  local top="$1" name="$2" r
  echo "=== $name"
  jq --arg t "$top" '.hdl_toplevel = $t' "$BASE" > "$tmp" || return 1
  cp "$tmp" "$REC/$name.request.json"
  # </dev/null: klt would otherwise consume the caller's stdin, which is the
  # module list this loop is reading from.
  "$KLT" sta "$tmp" --format json > "$REC/$name.json" 2> "$REC/$name.stderr" </dev/null
  r=$?
  if [ $r -ne 0 ]; then
    echo "--- $name exited $r (recorded as it ran)" >&2
    # klt writes its failure envelope to stderr and nothing to stdout, so the
    # record's .json would be empty. Copy the envelope across, the same
    # convention records/20261028T050500Z-a53678d/ already uses for the
    # place-and-route failure.
    [ -s "$REC/$name.json" ] || cp "$REC/$name.stderr" "$REC/$name.json"
  fi
  return $r
}

mapfile -t module_lines <<< "$free_now"
for line in "${module_lines[@]}"; do
  [ -n "$line" ] || continue
  slug=${line%%$'\t'*}
  name=${line#*$'\t'}
  run_one "$name" "$slug" || rc=1
done

# Negative control: the macro-bearing top is expected NOT to link. Its failure
# envelope is the evidence that pre-route timing of jpeg_codec_top is
# unreachable while #31 is open, so a zero exit here is the surprise.
if [ ${#ONLY[@]} -eq 0 ]; then
  if run_one "$TOP" "negative-control-$TOP"; then
    echo "!!! $TOP linked unexpectedly -- the macro LEF gap may be closed" >&2
    rc=1
  else
    echo "    (expected: ORD-2013, no LEF master for gf180_sram_256x32)"
  fi
fi

{
  echo "klt:      $("$KLT" --version)"
  echo "openroad: $(openroad -version 2>&1 | head -1)"
  echo "pdk:      $PDK, open_pdks $OPEN_PDKS_REV (ciel $CIEL_VERSION)"
  echo "git:      $(git rev-parse HEAD)"
  echo "netlist:  flow/$NETLIST sha256:$(sha256sum "$NETLIST" | cut -d' ' -f1)"
  echo "request:  flow/$BASE (verilog mode, no macros[]; no gf180_sram_256x32 LEF published)"
  echo
  echo "# As reported by the responses themselves, not recomputed here:"
  python3 -I - "$REC" <<'PY'
import glob, json, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.json'))):
    if f.endswith('.request.json'):
        continue
    try:
        d = json.load(open(f))
    except (ValueError, OSError) as exc:
        print('  %-34s UNREADABLE RESPONSE: %s' % (os.path.basename(f)[:-5], exc))
        continue
    name = os.path.basename(f)[:-5]
    if 'error' in d:
        print('  %-34s failure envelope only (no provenance block); see %s.stderr'
              % (name, name))
        continue
    p = d.get('provenance') or {}
    print('  %-34s klt %s / engine %s / pdk %s / input %s (%s)'
          % (name, p.get('klt_version'), d.get('engine_version'),
             (p.get('pdk') or {}).get('version'),
             (p.get('input') or {}).get('content_hash'),
             (p.get('input') or {}).get('role')))
PY
} > "$REC/versions.txt"

python3 -I - "$REC" <<'PY' > "$REC/summary.md"
import json, glob, os, sys
rec = sys.argv[1]
rows, failed = [], []
for f in sorted(glob.glob(os.path.join(rec, '*.json'))):
    if f.endswith('.request.json'):
        continue
    name = os.path.basename(f)[:-5]
    try:
        d = json.load(open(f))
    except (ValueError, OSError):
        d = {'status': 'unreadable response'}
    if not isinstance(d, dict) or d.get('status') != 'ok' or not d.get('corners'):
        try:
            req = json.load(open(os.path.join(rec, name + '.request.json')))
        except (ValueError, OSError):
            req = {}
        failed.append((name, d if isinstance(d, dict) else {}, req))
        continue
    for c in d['corners']:
        rows.append((name, d.get('hdl_toplevel'), c))

print('# Pre-route STA summary: cell delays only, no wire parasitics\n')
print('Generated by `flow/sta-preroute.sh`. `klt sta` verilog mode,')
print('`geometry_source: netlist_estimate`, 20 ns clock, 2 ns input and output')
print('delay, five `spec/codec.md` §10 views in one request per module.')
print('Paths through `gf180_sram_256x32` are ABSENT, not merely untimed: the')
print('macro-bearing `jpeg_codec_top` and `jc_sram_wrap` cannot be linked')
print('without the macro LEF. Submodule-scoped runs constrain each module\'s')
print('own ports with a fixed I/O delay and do not see the real cross-boundary')
print('driver or load, so inter-module paths are not covered either.\n')

print('## Per module, per view\n')
print('| module | view | status | setup slack (ns) | hold slack (ns) | setup viol | '
      'hold viol | fmax (MHz) | worst setup startpoint | worst setup endpoint | constraints |')
print('|' + '---|' * 11)
for name, top, c in rows:
    wsp = c.get('worst_setup_path') or {}
    print('| `%s` | `%s` | %s | %s | %s | %s | %s | %s | `%s` | `%s` | %s |' % (
        top, c['corner'], c.get('timing_status'),
        c.get('worst_slack_ns'), c.get('worst_hold_slack_ns'),
        c.get('setup_violation_count'), c.get('hold_violation_count'),
        c.get('fmax_mhz'), wsp.get('startpoint'), wsp.get('endpoint'),
        (c.get('constraint_completeness') or {}).get('status')))

print('\n## Total negative slack, worst hold path, constraint completeness\n')
print('| module | view | TNS setup (ns) | TNS hold (ns) | worst hold startpoint | '
      'worst hold endpoint | unconstrained endpoints | unclocked registers |')
print('|' + '---|' * 8)
for name, top, c in rows:
    cc = c.get('constraint_completeness') or {}
    ue = cc.get('unconstrained_endpoints') or {}
    ur = cc.get('unclocked_registers') or {}
    whp = c.get('worst_hold_path') or {}
    print('| `%s` | `%s` | %s | %s | `%s` | `%s` | %s | %s |' % (
        top, c['corner'], c.get('total_negative_slack_ns'),
        c.get('total_negative_hold_slack_ns'),
        whp.get('startpoint'), whp.get('endpoint'),
        ue.get('count'), ur.get('count')))

viol = [(top, c['corner'], c.get('worst_slack_ns'), c.get('setup_violation_count'),
         (c.get('worst_setup_path') or {}).get('startpoint'),
         (c.get('worst_setup_path') or {}).get('endpoint'))
        for name, top, c in rows if (c.get('worst_slack_ns') or 0) < 0]
print('\n## Setup findings: negative slack, worst first\n')
if not viol:
    print('None: every module that linked meets setup at every view.')
else:
    print('| module | view | worst setup slack (ns) | setup violations | startpoint | endpoint |')
    print('|' + '---|' * 6)
    for v in sorted(viol, key=lambda r: r[2]):
        print('| `%s` | `%s` | **%s** | %s | `%s` | `%s` |' % v)

hviol = [(top, c['corner'], c.get('worst_hold_slack_ns'), c.get('hold_violation_count'))
         for name, top, c in rows if (c.get('worst_hold_slack_ns') or 0) < 0]
print('\n## Hold findings: negative slack, worst first\n')
if not hviol:
    print('None: every module that linked meets hold at every view.')
else:
    print('| module | view | worst hold slack (ns) | hold violations |')
    print('|' + '---|' * 4)
    for v in sorted(hviol, key=lambda r: r[2]):
        print('| `%s` | `%s` | **%s** | %s |' % v)

print('\n## Requests that did not produce timing\n')
if not failed:
    print('None.')
else:
    print('Recorded as they ran; the response `*.json` holds klt\'s failure')
    print('envelope, copied from `*.stderr` because a failing run writes')
    print('nothing to stdout.\n')
    print('| response | requested hdl_toplevel | engine error | message |')
    print('|' + '---|' * 4)
    for name, d, req in failed:
        msg = ((d.get('error') or {}).get('message')
               or d.get('status') or 'no response')
        msg = msg.split(' -- openroad invocation:')[0].strip()
        tag = '—'
        for t in ('ORD-2013', 'STA-1390', 'STA-0198', 'no such variable'):
            if t in msg:
                tag = t
                break
        if len(msg) > 300:
            msg = msg[:300] + '…'
        print('| `%s.json` | `%s` | `%s` | %s |'
              % (name, req.get('hdl_toplevel', '?'), tag,
                 msg.replace('|', '\\|').replace('\n', ' ')))
PY

# Responses carry repo-relative paths already; normalise anything host-specific
# that leaks through before the record is committed.
ROOT=$(git rev-parse --show-toplevel)
sed -i "s#$ROOT/#./#g; s#$HOME#~#g" "$REC"/*.json "$REC"/*.stderr "$REC"/*.txt
case "$REC" in
  /*) echo "records in $REC" ;;
   *) echo "records in flow/$REC" ;;
esac
exit $rc
