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

echo
if [ "$fail" -ne 0 ]; then echo "lint FAILED"; exit 1; fi
echo "lint OK"
