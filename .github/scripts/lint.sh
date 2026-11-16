#!/usr/bin/env bash
# The lint the CI `lint` job runs. Runnable locally, identically:
#
#   bash .github/scripts/lint.sh
#
# Needs python3 and, for the RTL leg, verilator (skipped with a message when
# absent). Needs no PDK and no klt: step 9 drives the flow wrappers with a
# stub KLT (plus jq; skipped with a message when absent) and fabricates the
# one SOURCES file flow/pdk.env insists on, in a scratch PDK_ROOT.
#
# The PDK-free legs of 2AMLogic/gf180-polysynth's .github/scripts/lint.sh
# (read at 010efac); its block-specific legs are not carried over.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
step() { echo; echo "=== $*"; }
bad()  { echo "FAIL: $*" >&2; fail=1; }

step "1. Python sources compile"
py_n=0
while IFS= read -r -d '' f; do
  py_n=$((py_n + 1))
  python3 -m py_compile "$f" || bad "python compile: $f"
done < <(git ls-files -z '*.py')
[ "$py_n" -eq 0 ] && echo "skipped: no tracked *.py"

step "2. Every JSON document is well-formed"
while IFS= read -r -d '' f; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" \
    || bad "malformed JSON: $f"
done < <(git ls-files -z '*.json')

step "3. Shell scripts parse"
while IFS= read -r -d '' f; do
  bash -n "$f" || bad "shell syntax: $f"
done < <(git ls-files -z '*.sh')

step "4. RTL is Verilator -Wall lint-clean"
rtl=()
while IFS= read -r -d '' f; do rtl+=("$f"); done < <(git ls-files -z 'rtl/*.v' 'rtl/*.sv')
if [ "${#rtl[@]}" -eq 0 ]; then
  echo "skipped: no RTL under rtl/ yet"
elif ! command -v verilator > /dev/null; then
  echo "skipped: no verilator on PATH"
else
  verilator --lint-only -Wall -Wno-MULTITOP -Irtl "${rtl[@]}" || bad "verilator lint"
fi

step "5. Reference images regenerate to the committed SHA256SUMS"
python3 verification/images/gen_images.py --check || bad "reference image hashes"

step "6. No absolute host paths leaked into committed sources"
# The prototype this repo came from had host-bound absolute paths in three
# scripts; this is the check that stops them coming back.
#
# The pattern deliberately requires a character class after the prefix rather
# than matching the bare prefix: a bare-prefix pattern matches THIS FILE,
# since the pattern and the failure message both contain the prefix
# literally. A real leak is always a prefix followed by a user name.
#
# `.loom/`, `.claude/` and `.agents/` are vendored third-party agent tooling, not sources
# of this block: their docs and example configs legitimately show host paths,
# and we do not edit them. Excluding them keeps this check pointed at what it
# is for. If the exclusion ever hides a real leak, it will be in a file we did
# not write, and `git ls-files` still lists it.
if git ls-files \
   | grep -vE '^\.(loom|claude|agents)/' \
   | xargs grep -lIE '/Users/[a-z]|/home/[a-z]+/dev' 2>/dev/null | grep . ; then
  bad "the files above contain an absolute host path"
fi

step "7. spec/README.md indexes every tracked decision record"
# Filename-keyed, both directions: two records share 0001 and two share
# 0005, so record numbers cannot key the match, and the `codec.md` row
# (which links `(codec.md)`, not into decision-records/) is excluded by the
# `decision-records/` anchor. The reverse loop strips a trailing `#anchor`
# and then any link title (anchor first: a title may itself contain `#`)
# before the tracked-file check, so an anchored or titled prose link is not
# a false "not tracked" — while index rows must still be bare paths. Both
# loops are fed by process substitution,
# never a pipe: `bad()` sets `fail` in the parent shell, and under
# `set -uo pipefail` without `lastpipe` a piped `while` loop would print
# FAIL lines from a subshell and still exit 0.
idx=spec/README.md
rec_n=0
while IFS= read -r -d '' f; do
  rec_n=$((rec_n + 1))
  grep -qF "(decision-records/$(basename "$f"))" "$idx" \
    || bad "no index row in $idx for record: $f"
done < <(git ls-files -z 'spec/decision-records/*.md')
[ "$rec_n" -eq 0 ] && echo "skipped: no tracked records under spec/decision-records/"
while IFS= read -r target; do
  git ls-files --error-unmatch -- "spec/decision-records/$target" > /dev/null 2>&1 \
    || bad "index row links a file that is not tracked: spec/decision-records/$target"
done < <(grep -oE '\(decision-records/[^)]+\)' "$idx" \
         | sed -e 's#^(decision-records/##' -e 's#)$##' \
              -e 's/#.*$//' -e 's/[[:space:]].*$//')

step "8. run_tb.py contract test (no cocotb or simulator needed)"
# The runner is the verdict gate for every cocotb bench; this pins its
# exit-code contract and executed-test counting without cocotb installed.
python3 verification/common/test_run_tb.py || bad "run_tb.py contract test"

step "9. flow watchdog bounds every klt call (stub-driven, PDK-free; issue #156)"
# Every "$KLT" call in the flow wrappers is bounded by flow/klt-watchdog.sh.
# Driven here with a stub klt that records its pids and hangs (or exits) on
# command, so no engine, no PDK and no klt install is involved. pdk.env
# still refuses to source without a SOURCES file under PDK_ROOT, so the
# harness fabricates one carrying the pin read from flow/pdk.env (never a
# hardcoded revision). Each wrapper run is capped by an outer `timeout 60`
# and its rc plus a caller-survived sentinel land in the run's .out file:
# if the watchdog ever signalled its caller's own process group, the
# sentinel subshell would die before echoing, and if the watchdog failed to
# bound a hang the outer timeout fires (60 s, distinguishable by the missing
# "klt-watchdog: timed out" line the real expiry prints).
if ! command -v jq > /dev/null 2>&1; then
  echo "skipped: no jq on PATH (needed to drive flow/sta-preroute.sh)"
else
  wd="$(mktemp -d)"
  wd_cleanup() {
    if [ -f "$wd/all-pids" ]; then
      while read -r p; do kill -KILL "$p" 2> /dev/null; done < "$wd/all-pids"
    fi
    rm -rf "$wd"
  }
  trap wd_cleanup EXIT
  mkdir -p "$wd/bin" "$wd/pdk/gf180mcuD" "$wd/rec"
  # The stub runs below must leave flow/ exactly as they found it -- checked
  # as a before/after diff of `git status --porcelain`, so this step also
  # passes on a worktree with unrelated uncommitted changes.
  wd_dirty_before=$(git status --porcelain -- flow/)
  printf 'open_pdks %s\n' "$(sed -n 's/^export OPEN_PDKS_REV=//p' flow/pdk.env)" \
    > "$wd/pdk/gf180mcuD/SOURCES"

  cat > "$wd/bin/stub" <<'STUB'
#!/usr/bin/env bash
# Test double for klt (lint step 9, issue #156). Mode via STUB_MODE:
#   hang       always hang (default): spawn a sleeping child and wait on it
#   synthesize hang only when $1 is synthesize (smoke's later stages run on)
#   negctl     hang only when the request's hdl_toplevel is jpeg_codec_top
#              (sta-preroute's negative control)
#   pass       exit 0 immediately, creating the request's outputs.dir with a
#              report.json and a .ys so synthesize.sh's post-processing runs
#   fail       exit 7 immediately (the watchdog must not mask a real status)
# Leader and child pids are appended to KLT_STUB_PIDFILE for the
# no-surviving-descendant assertions.
set -u
case "${1:-}" in --version) exit 0 ;; esac
mode="${STUB_MODE:-hang}"
if [ "$mode" = pass ]; then
  d=$(jq -r '.outputs.dir // empty' "${2:-}" 2> /dev/null)
  if [ -n "$d" ]; then
    mkdir -p "$d"
    printf '{}\n' > "$d/report.json"
    : > "$d/stub.ys"
  fi
  exit 0
fi
if [ "$mode" = fail ]; then
  echo "stub deliberate failure"
  echo "stub deliberate failure" >&2
  exit 7
fi
if [ "$mode" = synthesize ] && [ "${1:-}" != synthesize ]; then exit 0; fi
if [ "$mode" = negctl ]; then
  f="${2:-}"
  if [ ! -f "$f" ] || ! grep -q '"hdl_toplevel": "jpeg_codec_top"' "$f"; then
    exit 0
  fi
fi
sleep 3000 &
printf '%s %s\n' "$$" "$!" >> "${KLT_STUB_PIDFILE:?}"
wait "$!"
STUB
  chmod +x "$wd/bin/stub"

  wd_run() {  # wd_run <mode> <out-base> <wrapper...>  (outer cap 60 s)
    local mode="$1" base="$2"
    shift 2
    : > "$wd/last-pids"
    (
      env PDK_ROOT="$wd/pdk" KLT_TIMEOUT=2 KLT="$wd/bin/stub" \
          STUB_MODE="$mode" KLT_STUB_PIDFILE="$wd/last-pids" \
          timeout 60 "$@"
      echo "caller-survived rc=$?"
    ) > "$base.out" 2> "$base.err"
    cat "$wd/last-pids" >> "$wd/all-pids" 2> /dev/null
  }

  wd_no_survivors() {  # wd_no_survivors <label>
    local label="$1" child i
    child=$(tail -n 1 "$wd/last-pids" 2> /dev/null | awk '{print $2}')
    if [ -z "$child" ]; then
      bad "$label: stub recorded no child pid to check"
      return
    fi
    for i in 1 2 3 4 5 6; do
      kill -0 "$child" 2> /dev/null || break
      sleep 0.5
    done
    if kill -0 "$child" 2> /dev/null; then
      bad "$label: stub child $child survived the watchdog kill"
      kill -KILL "$child" 2> /dev/null
    fi
  }

  # synthesize.sh does `rm -rf netlist` before its klt call, so the stub
  # runs below would delete the committed baseline that the byte-identical
  # contract protects. Snapshot and restore it around them.
  cp -r flow/netlist "$wd/netlist-backup"

  # --check hang: bounded despite no longer exec'ing; 124; diagnostics that
  # name the stub and its child; the caller (this lint) survived the kill.
  wd_run hang "$wd/chk" bash flow/synthesize.sh --check
  grep -qx 'caller-survived rc=124' "$wd/chk.out" \
    || bad "--check hang: expected wrapper rc=124 with the caller alive (tail: $(tail -n 2 "$wd/chk.out"))"
  grep -q 'klt-watchdog: timed out after 2s' "$wd/chk.err" \
    || bad "--check hang: no watchdog expiry message on stderr"
  grep -q 'diagnostics in ' "$wd/chk.err" \
    || bad "--check hang: stderr does not name the diagnostic file"
  diag=$(ls flow/klt-watchdog-check-*.diag.txt 2> /dev/null | head -n 1)
  if [ -z "$diag" ]; then
    bad "--check hang: no diagnostic file in flow/"
  else
    grep -q "$wd/bin/stub" "$diag" || bad "--check hang: diagnostic does not name the stub"
    grep -q "pid $(tail -n 1 "$wd/last-pids" | awk '{print $2}')" "$diag" \
      || bad "--check hang: diagnostic does not name the stub's child"
  fi
  wd_no_survivors "--check hang"
  rm -f flow/klt-watchdog-check-*.diag.txt

  # --check propagates klt's own exit status unchanged (stub exits 7).
  wd_run fail "$wd/chkf" bash flow/synthesize.sh --check
  grep -qx 'caller-survived rc=7' "$wd/chkf.out" \
    || bad "--check fail: exit status 7 not propagated (tail: $(tail -n 1 "$wd/chkf.out"))"

  # --check with "-" against a regular caller file: klt_bounded must
  # DUPLICATE the caller's descriptors, not reopen /dev/fd/N (a fresh open
  # applies O_TRUNC, resets the offset, drops O_APPEND, and the two "-"
  # streams would collide at offset 0). With both caller streams merged into
  # one file, the pre-wrapper line, the stub's stdout line, the stub's
  # stderr line and the post-wrapper status must all survive, in order.
  {
    echo "PRE-wrapper-line"
    env PDK_ROOT="$wd/pdk" KLT_TIMEOUT=2 KLT="$wd/bin/stub" \
        STUB_MODE=fail KLT_STUB_PIDFILE="$wd/last-pids" \
        timeout 60 bash flow/synthesize.sh --check
    echo "POST-wrapper-line rc=$?"
  } > "$wd/redir.out" 2>&1
  tr '\n' '|' < "$wd/redir.out" \
    | grep -q 'PRE-wrapper-line|stub deliberate failure|stub deliberate failure|POST-wrapper-line rc=7|' \
    || bad "--check redir: '-' passthrough truncated, collided or reordered the caller's file (cat: $(cat "$wd/redir.out"))"

  # Main path hang: bounded, 124, no descendant left.
  wd_run hang "$wd/main" bash flow/synthesize.sh
  grep -qx 'caller-survived rc=124' "$wd/main.out" \
    || bad "synthesize hang: expected wrapper rc=124 (tail: $(tail -n 1 "$wd/main.out"))"
  grep -q 'klt-watchdog: timed out after 2s' "$wd/main.err" \
    || bad "synthesize hang: no watchdog expiry message on stderr"
  diag=$(ls flow/klt-watchdog-[0-9]*.diag.txt 2> /dev/null | head -n 1)
  [ -n "$diag" ] || bad "synthesize hang: no diagnostic file in flow/"
  wd_no_survivors "synthesize hang"
  rm -f flow/klt-watchdog-[0-9]*.diag.txt

  # Main path, stub fails fast: the watchdog must not mask the real status,
  # and the main path's "-" stderr must carry the stub's failure line.
  wd_run fail "$wd/mainf" bash flow/synthesize.sh
  grep -qx 'caller-survived rc=7' "$wd/mainf.out" \
    || bad "synthesize fail: stub's exit status 7 was not propagated unchanged (tail: $(tail -n 1 "$wd/mainf.out"))"
  grep -q 'stub deliberate failure' "$wd/mainf.err" \
    || bad "synthesize fail: stub stderr did not reach the caller's stderr via '-'"

  # Main path, stub exits 0 fast, well inside the bound: exit 0, no
  # diagnostics, no watchdog output at all.
  wd_run pass "$wd/mainp" bash flow/synthesize.sh
  grep -qx 'caller-survived rc=0' "$wd/mainp.out" \
    || bad "synthesize pass: healthy stub run did not exit 0 (tail: $(tail -n 1 "$wd/mainp.out"))"
  ls flow/klt-watchdog-*.diag.txt > /dev/null 2>&1 \
    && bad "synthesize pass: healthy run wrote diagnostic files"
  grep -q 'klt-watchdog' "$wd/mainp.err" \
    && bad "synthesize pass: healthy run printed watchdog output"
  rm -rf flow/netlist
  cp -r "$wd/netlist-backup" flow/netlist

  # synthesize-optc.sh hang: the failure path records it and exits non-zero.
  wd_run hang "$wd/optc" bash flow/synthesize-optc.sh
  grep -qx 'caller-survived rc=1' "$wd/optc.out" \
    || bad "optc hang: expected wrapper rc=1 (tail: $(tail -n 1 "$wd/optc.out"))"
  grep -q 'klt-watchdog: timed out after 2s' "$wd/optc.err" \
    || bad "optc hang: no watchdog expiry message on stderr"
  diag=$(ls flow/klt-watchdog-optc-*.diag.txt 2> /dev/null | head -n 1)
  [ -n "$diag" ] || bad "optc hang: no diagnostic file in flow/"
  wd_no_survivors "optc hang"
  rm -rf flow/netlist-optc
  rm -f flow/klt-watchdog-optc-*.diag.txt

  # smoke/run.sh: only the synthesize stage hangs; the flow must record it
  # (rc=124) and carry on, exiting non-zero at the end.
  ls -1 flow/smoke/records > "$wd/rec-before" 2> /dev/null
  smoke_klt=$([ -d flow/smoke/.klt ] && echo y || echo n)
  wd_run synthesize "$wd/smoke" bash flow/smoke/run.sh
  grep -qx 'caller-survived rc=1' "$wd/smoke.out" \
    || bad "smoke hang: expected wrapper rc=1 (tail: $(tail -n 1 "$wd/smoke.out"))"
  grep -q -- '--- synthesize FAILED (rc=124)' "$wd/smoke.err" \
    || bad "smoke hang: synthesize stage not recorded as FAILED (rc=124)"
  smoke_rec=$(sed -n 's/^records in flow\/smoke\///p' "$wd/smoke.out" | head -n 1)
  if [ -z "$smoke_rec" ]; then
    bad "smoke hang: could not locate the run's record directory"
  else
    [ -f "flow/smoke/$smoke_rec/synthesize.watchdog.diag.txt" ] \
      || bad "smoke hang: no synthesize.watchdog.diag.txt in the run's record directory"
  fi
  wd_no_survivors "smoke hang"
  while IFS= read -r d; do
    grep -qxF "$d" "$wd/rec-before" || rm -rf "flow/smoke/records/$d"
  done < <(ls -1 flow/smoke/records 2> /dev/null)
  [ "$smoke_klt" = y ] || rm -rf flow/smoke/.klt

  # sta-preroute.sh negative control timed out: rc=124 must fail the run --
  # never masquerade as the expected ORD-2013 non-linkage.
  wd_run negctl "$wd/negctl" bash flow/sta-preroute.sh --out "$wd/rec"
  grep -qx 'caller-survived rc=1' "$wd/negctl.out" \
    || bad "sta-preroute timeout: expected wrapper rc=1 (tail: $(tail -n 1 "$wd/negctl.out"))"
  grep -q '(expected: ORD-2013' "$wd/negctl.err" \
    && bad "sta-preroute timeout: negative control reported the expected-failure line for a timed-out run"
  grep -q 'hit the watchdog bound (rc=124)' "$wd/negctl.err" \
    || bad "sta-preroute timeout: no watchdog-bound failure message on stderr"
  [ -f "$wd/rec/negative-control-jpeg_codec_top.watchdog.diag.txt" ] \
    || bad "sta-preroute timeout: no watchdog diagnostic in the --out record"
  wd_no_survivors "sta-preroute timeout"

  # Nothing the stub runs did may survive into the worktree.
  if ! diff \
      <(printf '%s\n' "$wd_dirty_before") \
      <(printf '%s\n' "$(git status --porcelain -- flow/)") > /dev/null; then
    diff <(printf '%s\n' "$wd_dirty_before") \
      <(printf '%s\n' "$(git status --porcelain -- flow/)") | sed -n '3,$p'
    bad "watchdog tests left flow/ dirty (diff above)"
  fi
fi

echo
if [ "$fail" -ne 0 ]; then echo "lint FAILED"; exit 1; fi
echo "lint OK"
