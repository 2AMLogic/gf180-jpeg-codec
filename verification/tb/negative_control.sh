#!/usr/bin/env bash
# Negative control: the injected-bug build must exit exactly 1 (the suite ran
# and a test failed) on each simulator. Any other status -- 0, or 2 for a suite
# that did not run -- fails this script.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0
for sim in icarus verilator; do
  python3 verification/common/run_tb.py --sim "$sim" --define INJECT_BUG_ENV=1 >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then echo "$sim: negative control exit $rc (ok)"
  else echo "FAIL: $sim: negative control exited $rc, expected 1" >&2; fail=1; fi
done
exit "$fail"
