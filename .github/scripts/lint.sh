#!/usr/bin/env bash
# The lint the CI `lint` job runs. Runnable locally, identically:
#
#   bash .github/scripts/lint.sh
#
# Needs python3 and, for the RTL leg, verilator (skipped with a message when
# absent). Needs no PDK and no klt.
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
  verilator --lint-only -Wall -Irtl "${rtl[@]}" || bad "verilator lint"
fi

echo
if [ "$fail" -ne 0 ]; then echo "lint FAILED"; exit 1; fi
echo "lint OK"
