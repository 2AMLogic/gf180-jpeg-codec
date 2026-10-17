#!/usr/bin/env bash
# The lint the CI `lint` job runs. Runnable locally, identically:
#
#   bash .github/scripts/lint.sh
#
# Vendored-and-adapted from 2AMLogic/gf180-polysynth (PDK-free legs only).
# Needs python3 and (for step 4) verilator. Needs no PDK and no klt.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
step() { echo; echo "=== $*"; }
bad()  { echo "FAIL: $*" >&2; fail=1; }

step "1. Python sources compile"
python3 -m compileall -q \
  verification/common/run_tb.py verification/tb/test_smoke.py || bad "python compile"

step "2. Every JSON document is well-formed"
while IFS= read -r f; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" \
    || bad "malformed JSON: $f"
done < <(git ls-files '*.json')

step "3. Shell scripts parse"
while IFS= read -r f; do
  bash -n "$f" || bad "shell syntax: $f"
done < <(git ls-files '*.sh')

step "4. RTL is Verilator -Wall lint-clean"
if command -v verilator > /dev/null; then
  verilator --lint-only -Wall -Irtl --top-module smoke_placeholder \
    rtl/smoke_placeholder.v || bad "verilator lint"
else
  echo "skipped: no verilator on PATH"
fi

step "5. No absolute host paths leaked into committed sources"
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

echo
if [ "$fail" -ne 0 ]; then echo "lint FAILED"; exit 1; fi
echo "lint OK"
