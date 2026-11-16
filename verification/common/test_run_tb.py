#!/usr/bin/env python3
"""Contract tests for verification/common/run_tb.py, the cocotb runner wrapper.

run_tb.py is the verdict gate for every cocotb bench in this repo, and it has
a history of silent contract defects found by hand (#27 stale GOLDEN path,
#122 dead TB constant, #130 a --testcase matching no test reporting "N/N
passed" over zero executed tests). This file is the guard against a fourth:
it pins the runner's exit-code contract and the executed-test counting, and
needs no cocotb, no simulator and no PDK, so CI (`.github/scripts/lint.sh`)
can run it anywhere.

    python3 verification/common/test_run_tb.py

Exit 0 every contract held, 1 otherwise. No test framework: CI has no pytest,
and lint.sh is already the repo's CI check idiom.
"""

import contextlib
import io
import sys
import tempfile
import types
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import run_tb  # noqa: E402


# --- results.xml fixtures --------------------------------------------------
#
# The shape cocotb's XUnitReporter writes (verified against the installed
# cocotb 2.1.0, cocotb/_xunit_reporter.py): <testsuites> > <testsuite> >
# <testcase>, where a skipped test is a <testcase> with a <skipped/> child, a
# failed one carries <failure/>, and an unexpected error carries <error/>.
# cocotb's get_results() reads only the <testsuite> attributes, so it counts
# skipped entries as tests -- the defect this file pins. Test names may be
# parametrized ("test_x/case=3"), so nothing here assumes a plain identifier.

_STATUS_CHILD = {
    "passed": "",
    "skipped": "<skipped/>",
    "failed": '<failure message="assertion"/>',
    "error": '<error message="unexpected"/>',
}


def make_results_xml(cases):
    """Build a cocotb-style results.xml body from (name, status) pairs."""
    counts = {"passed": 0, "skipped": 0, "failed": 0, "error": 0}
    rows = []
    for name, status in cases:
        counts[status] += 1
        child = _STATUS_CHILD[status]
        inner = f"\n      {child}\n    " if child else ""
        rows.append(
            f'    <testcase classname="test_dct" name="{name}" time="0.001">{inner}</testcase>'
        )
    suite = (
        f'  <testsuite name="test_dct" errors="{counts["error"]}"'
        f' failures="{counts["failed"]}" skipped="{counts["skipped"]}"'
        f' tests="{len(cases)}" time="0.001">'
    )
    return "\n".join(
        ['<?xml version="1.0" encoding="utf-8"?>',
         '<testsuites name="cocotb tests">', suite]
        + rows
        + ["  </testsuite>", "</testsuites>", ""]
    )


# --- a cocotb_tools.runner stub ---------------------------------------------
#
# main() imports cocotb_tools.runner at call time; with this stub on
# sys.modules the whole verdict path runs in CI with no cocotb installed.
# The stub's get_results mirrors cocotb's real one (it counts the
# <testsuite> attributes, skipped entries included) so a regression back to
# get_results()-based verdicts is caught, not masked. The fake runner's
# build/test do no simulation: they create the build directory and write the
# fixture XML where main() expects the results file.

class _FakeRunner:
    def __init__(self, xml_body):
        self._xml_body = xml_body

    def build(self, **kwargs):
        Path(kwargs["build_dir"]).mkdir(parents=True, exist_ok=True)

    def test(self, **kwargs):
        results_xml = Path(kwargs["results_xml"])
        results_xml.write_text(self._xml_body)
        return str(results_xml)


@contextlib.contextmanager
def fake_cocotb(xml_body):
    def get_results(results_xml_file):
        if not Path(results_xml_file).is_file():
            raise RuntimeError(f"results file {results_xml_file} not found")
        num_tests = num_failed = 0
        for suite in ET.parse(results_xml_file).getroot().findall("testsuite"):
            num_tests += int(suite.get("tests", 0))
            num_failed += int(suite.get("failures", 0)) + int(suite.get("errors", 0))
        return num_tests, num_failed

    pkg = types.ModuleType("cocotb_tools")
    mod = types.ModuleType("cocotb_tools.runner")
    mod.get_runner = lambda sim: _FakeRunner(xml_body)
    mod.get_results = get_results
    pkg.runner = mod
    saved = {name: sys.modules.get(name) for name in ("cocotb_tools", "cocotb_tools.runner")}
    sys.modules["cocotb_tools"] = pkg
    sys.modules["cocotb_tools.runner"] = mod
    try:
        yield
    finally:
        for name, old in saved.items():
            if old is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = old


def run_main(xml_body):
    """Run run_tb.main() against the fake runner; return (exit status, stderr)."""
    err = io.StringIO()
    with fake_cocotb(xml_body), contextlib.redirect_stderr(err):
        with tempfile.TemporaryDirectory() as d:
            code = run_tb.main(["--source", "jc_dct.v", "--toplevel", "jc_dct",
                                "--test-module", "test_dct", "--test-dir", d])
    return code, err.getvalue()


# --- the contract -----------------------------------------------------------

def test_missing_arguments_exit_2():
    # The argument contract (#122 class): with nothing to run the runner must
    # refuse with EXIT_DID_NOT_RUN -- and must do so without cocotb installed,
    # which is why the check precedes the cocotb import in main().
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        assert run_tb.main([]) == run_tb.EXIT_DID_NOT_RUN
        assert run_tb.main(["--source", "jc_dct.v"]) == run_tb.EXIT_DID_NOT_RUN
        assert run_tb.main(["--toplevel", "jc_dct"]) == run_tb.EXIT_DID_NOT_RUN
        assert run_tb.main(["--test-module", "test_dct"]) == run_tb.EXIT_DID_NOT_RUN
        assert run_tb.main(["--test-dir", "."]) == run_tb.EXIT_DID_NOT_RUN


def test_help_exits_zero():
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            run_tb.main(["--help"])
    except SystemExit as exc:
        assert exc.code == 0, f"--help must exit 0, got {exc.code!r}"
    else:
        raise AssertionError("--help did not exit")
    assert "--testcase" in out.getvalue(), "--help must document --testcase"


def test_count_executed_counts_only_tests_that_ran():
    # The #130 case, at the counter level: one selected test plus five
    # filtered-out entries must count as 1 executed, not 6.
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "results.xml"
        p.write_text(make_results_xml([
            ("test_worked_examples", "passed"),
            ("test_directed_blocks", "skipped"),
            ("test_random_blocks", "skipped"),
            ("test_backpressure", "skipped"),
            ("test_cycle_budget", "skipped"),
            ("test_x/case=3", "skipped"),  # parametrized name
        ]))
        assert run_tb.count_executed(p) == (1, 0, 5), run_tb.count_executed(p)


def test_count_executed_all_skipped_is_zero_executed():
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "results.xml"
        p.write_text(make_results_xml([(f"t{i}", "skipped") for i in range(6)]))
        assert run_tb.count_executed(p) == (0, 0, 6), run_tb.count_executed(p)


def test_count_executed_counts_failures_and_errors():
    # failure and error children both mean an executed test failed; skipped
    # never counts as executed or failed.
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "results.xml"
        p.write_text(make_results_xml([
            ("a", "passed"), ("b", "failed"), ("c", "error"), ("d", "skipped"),
        ]))
        assert run_tb.count_executed(p) == (3, 2, 1), run_tb.count_executed(p)


def test_count_executed_missing_file_raises():
    try:
        run_tb.count_executed(Path(tempfile.gettempdir()) / "no-such-results.xml")
    except RuntimeError:
        pass
    else:
        raise AssertionError("a missing results file must raise, not report a verdict")


def test_count_executed_unreadable_file_raises():
    # A directory is not a readable results file; neither is garbage.
    with tempfile.TemporaryDirectory() as d:
        try:
            run_tb.count_executed(Path(d))
        except (RuntimeError, OSError):
            pass
        else:
            raise AssertionError("an unreadable results file must raise, not report a verdict")
        p = Path(d) / "results.xml"
        p.write_text("this is not xml")
        try:
            run_tb.count_executed(p)
        except RuntimeError:
            pass
        else:
            raise AssertionError("an unparseable results file must raise, not report a verdict")


def test_main_exit_0_when_all_executed_tests_pass():
    code, err = run_main(make_results_xml([("a", "passed"), ("b", "passed")]))
    assert code == run_tb.EXIT_OK, f"exit {code}: {err!r}"
    assert "2/2 passed" in err, err


def test_main_exit_1_when_executed_test_fails():
    # The executed-but-failed case must stay EXIT_FAILED (1), never be
    # mistaken for did-not-run.
    code, err = run_main(make_results_xml([("a", "passed"), ("b", "failed")]))
    assert code == run_tb.EXIT_FAILED, f"exit {code}: {err!r}"
    assert "1/2 passed" in err, err


def test_main_exit_2_when_nothing_executed():
    # THE #130 guard: a --testcase matching no test leaves only skipped
    # entries; the runner must exit EXIT_DID_NOT_RUN, not certify a pass.
    xml = make_results_xml([(f"t{i}", "skipped") for i in range(6)])
    code, err = run_main(xml)
    assert code == run_tb.EXIT_DID_NOT_RUN, f"a nothing-ran run exited {code}: {err!r}"


def test_main_pass_line_counts_executed_not_listed():
    # The valid-filter case from #130: one selected test among six entries
    # must report 1/1, with skip information appended -- never 6/6.
    xml = make_results_xml(
        [("test_worked_examples", "passed")] + [(f"t{i}", "skipped") for i in range(5)]
    )
    code, err = run_main(xml)
    assert code == run_tb.EXIT_OK, f"exit {code}: {err!r}"
    assert "1/1 passed" in err, f"pass line must count executed tests: {err!r}"
    assert "6/6 passed" not in err, f"pass line counted skipped entries: {err!r}"
    assert "5 skipped" in err, f"skip information must be appended: {err!r}"


def test_main_exit_2_when_xml_has_no_tests():
    code, err = run_main('<testsuites name="cocotb tests"><testsuite name="s" '
                         'errors="0" failures="0" skipped="0" tests="0" time="0">'
                         "</testsuite></testsuites>")
    assert code == run_tb.EXIT_DID_NOT_RUN, f"exit {code}: {err!r}"
    assert "no test" in err, err


def main():
    tests = [
        test_missing_arguments_exit_2,
        test_help_exits_zero,
        test_count_executed_counts_only_tests_that_ran,
        test_count_executed_all_skipped_is_zero_executed,
        test_count_executed_counts_failures_and_errors,
        test_count_executed_missing_file_raises,
        test_count_executed_unreadable_file_raises,
        test_main_exit_0_when_all_executed_tests_pass,
        test_main_exit_1_when_executed_test_fails,
        test_main_exit_2_when_nothing_executed,
        test_main_pass_line_counts_executed_not_listed,
        test_main_exit_2_when_xml_has_no_tests,
    ]
    failed = 0
    for test in tests:
        try:
            test()
        except AssertionError as exc:
            print(f"FAIL {test.__name__}: {exc}", file=sys.stderr)
            failed += 1
        except Exception as exc:  # a crash in a check is a failure of the check
            print(f"ERROR {test.__name__}: {type(exc).__name__}: {exc}", file=sys.stderr)
            failed += 1
        else:
            print(f"ok   {test.__name__}")
    total = len(tests)
    if failed:
        print(f"run_tb contract: {total - failed}/{total} checks passed -- {failed} FAILED",
              file=sys.stderr)
        return 1
    print(f"run_tb contract: {total}/{total} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
