#!/usr/bin/env python3
"""Tests for check_inventory_closure.py (issue #172).

The guard must fail loudly when a non-glob .py member does not resolve to a
file under the working directory. It used to silently drop such members, so
a wrong cwd checked zero members and reported OK.

Run: python3 -I .github/scripts/test_check_inventory_closure.py
"""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_inventory_closure.py"
REPO_ROOT = SCRIPT.parents[2]


def run_guard(cwd, *args):
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), *args],
        cwd=str(cwd), capture_output=True, text=True)


class TestGreenFromRoot(unittest.TestCase):
    """The documented repo-root invocation must stay green (items 1/9/10)."""

    def test_real_inventories_exit_zero_from_root(self):
        r = run_guard(
            REPO_ROOT,
            "manifests/attest/item1.inventory.json",
            "manifests/attest/item9.inventory.json",
            "manifests/attest/item10.inventory.json")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("inventory import closure: OK", r.stdout)

    def test_item9_checks_all_members_not_zero(self):
        r = run_guard(REPO_ROOT, "manifests/attest/item9.inventory.json")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        m = re.search(r"(\d+) \.py member\(s\) checked", r.stdout)
        self.assertIsNotNone(m, r.stdout)
        self.assertGreater(int(m.group(1)), 0)


class TestUnresolvedMemberFails(unittest.TestCase):
    """A non-glob .py member that resolves to no file must exit non-zero."""

    def test_wrong_cwd_exits_nonzero(self):
        # The issue's repro: same invocation from verification/ resolves no
        # member; the guard must not report OK on zero members.
        r = run_guard(REPO_ROOT / "verification",
                      "../manifests/attest/item9.inventory.json")
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertIn("does not resolve", r.stdout)
        self.assertIn("inventory import closure: FAIL", r.stdout)

    def test_misspelled_member_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as tmp:
            inv = Path(tmp) / "misspelled.inventory.json"
            inv.write_text(json.dumps({
                "sources": ["verification/rtl/run_stage_typo.py"]}))
            r = run_guard(REPO_ROOT, str(inv))
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertIn("does not resolve", r.stdout)


class TestMembersStillScoped(unittest.TestCase):
    """Globs and non-.py strings are still not members to resolve."""

    def test_glob_member_still_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            inv = Path(tmp) / "glob.inventory.json"
            inv.write_text(json.dumps(
                {"pattern": "verification/golden/test_*.py"}))
            r = run_guard(REPO_ROOT, str(inv))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_non_py_strings_ignored(self):
        # argv entries and .json/.sv paths never count as .py members.
        with tempfile.TemporaryDirectory() as tmp:
            inv = Path(tmp) / "misc.inventory.json"
            inv.write_text(json.dumps({
                "argv": ["python3", "-m", "unittest", "discover"],
                "sources": ["rtl/jpeg_codec_top.sv",
                            "manifests/gf180-jpeg-codec.json"]}))
            r = run_guard(REPO_ROOT, str(inv))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
