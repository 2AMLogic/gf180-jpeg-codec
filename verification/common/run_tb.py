#!/usr/bin/env python3
"""PDK-free runner for the cocotb testbench.

Drives the cocotb testbench straight through cocotb's own runner, so CI and a
cold-start contributor need only `iverilog` / `verilator` and `pip install
cocotb`, with no klayout-tools install and no PDK.

    python3 verification/common/run_tb.py --source jc_dct.v --source jc_dct1d.v \
        --source jc_xpose_rf.v --toplevel jc_dct --test-module test_dct \
        --test-dir verification/rtl
    python3 verification/common/run_tb.py ... --sim verilator
    python3 verification/common/run_tb.py ... --define INJECT_BUG_ENV=1   # expect exit 1

Normally driven through the wrappers in verification/rtl/, which set the
sources, top level, test module and test directory.

Vendored from 2AMLogic/gf180-polysynth tb/run_tb.py (see reuse.lock.json and
spec/decision-records/0001-harness-divergence.md for what differs).

Exit status is the test verdict, and the two failure codes are not
interchangeable:

    0  every test that executed passed
    1  the suite ran and at least one executed test failed
    2  the suite did not run -- no results XML, or no test executed
       (an empty XML, or every test filtered out by --testcase)

Anything that asserts a run *should* fail (the injected-bug negative controls)
must require 1, never merely non-zero: a build or import error also exits
non-zero while proving nothing.
"""

from __future__ import annotations

import argparse
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
RTL = ROOT / "rtl"
GOLDEN = ROOT / "verification" / "golden"

# No defaults: a wrapper (run_stage.py, run_top_*.py) sets these, or the caller
# passes --source / --toplevel / --test-module / --test-dir.
SOURCES: list[Path] = []
TOPLEVEL = ""
TEST_MODULE = ""
TEST_DIR = ""
TIMESCALE = ("1ns", "1ps")

EXIT_OK = 0
EXIT_FAILED = 1          # the suite ran, tests failed
EXIT_DID_NOT_RUN = 2     # no verdict exists: build/import error, empty XML, nothing executed


def count_executed(results_xml: Path) -> tuple[int, int, int]:
    """Count the tests that actually executed in a cocotb results XML.

    Returns (executed, failed, skipped): executed counts the <testcase>
    entries that ran to a verdict; failed counts the executed ones carrying
    <failure/> or <error/>; skipped counts the entries carrying <skipped/> --
    tests that were filtered out and never ran. Test names may be cocotb
    parametrizations ("test_x/case=3"), so the name attribute is never parsed.

    cocotb's own get_results() reads the <testsuite> attributes instead, and
    two cocotb behaviours make that wrong for a verdict: up to 2.0.x it
    records every test filtered out by --testcase as a <skipped/> entry while
    still counting it under `tests` (#130 -- a filtered run that executed
    nothing reported "N/N passed" and exited 0), and any cocotb version can
    mark a test skipped at runtime. Neither a skipped nor a never-listed test
    is a pass, so the verdict here is computed from this count.

    Raises RuntimeError when the file is missing or unparseable, so a read
    error can never degrade into a verdict of zero tests.
    """
    if not Path(results_xml).is_file():
        raise RuntimeError(f"results file {results_xml} not found")
    try:
        root = ET.parse(results_xml).getroot()
    except ET.ParseError as exc:
        raise RuntimeError(f"results file {results_xml} is unparseable: {exc}") from exc
    executed = failed = skipped = 0
    for testcase in root.iter("testcase"):
        if testcase.find("skipped") is not None:
            skipped += 1
            continue
        executed += 1
        if testcase.find("failure") is not None or testcase.find("error") is not None:
            failed += 1
    return executed, failed, skipped


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sim", default="icarus", choices=["icarus", "verilator"])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument(
        "--define",
        action="append",
        default=[],
        metavar="NAME[=VALUE]",
        help="Verilog `define passed to the build (repeatable).",
    )
    ap.add_argument("--source", action="append", default=None, metavar="FILE",
                    help="RTL source (repeatable, relative to rtl/); required unless a wrapper sets SOURCES")
    ap.add_argument("--toplevel", default=TOPLEVEL)
    ap.add_argument("--test-module", default=TEST_MODULE)
    ap.add_argument("--test-dir", default=TEST_DIR,
                    help="directory holding the cocotb bench module; sim_build/ lands under it; "
                         "required unless a wrapper sets TEST_DIR")
    ap.add_argument("--testcase", default=None, help="run a single named test")
    ap.add_argument("--waves", action="store_true")
    args = ap.parse_args(argv)

    # Argument check before anything else -- deliberately before the cocotb
    # import below, so a malformed invocation is refused with EXIT_DID_NOT_RUN
    # even where cocotb is not installed (the contract test relies on this).
    sources = [RTL / f for f in args.source] if args.source else SOURCES
    if not sources or not args.toplevel or not args.test_module or not args.test_dir:
        print("run_tb: no sources, toplevel, test module or test dir given "
              "(use --source, --toplevel, --test-module, --test-dir or a wrapper)", file=sys.stderr)
        return EXIT_DID_NOT_RUN

    # Imported here so --help works without cocotb installed.
    from cocotb_tools.runner import get_runner

    defines: dict[str, object] = {}
    for item in args.define:
        name, _, value = item.partition("=")
        defines[name] = value or 1

    test_dir = Path(args.test_dir).resolve()
    build_dir = test_dir / "sim_build" / args.sim / args.toplevel
    runner = get_runner(args.sim)
    try:
        runner.build(
            verilog_sources=sources,
            includes=[RTL],
            defines=defines,
            hdl_toplevel=args.toplevel,
            build_dir=build_dir,
            timescale=TIMESCALE,
            waves=args.waves,
            always=True,
        )
    except Exception as exc:                      # compile/elaborate failure
        # Not a verdict: nothing was tested. Distinguishing this from a real
        # test failure is the whole point of EXIT_DID_NOT_RUN.
        print(f"{args.sim}: the design did not build: {exc}", file=sys.stderr)
        return EXIT_DID_NOT_RUN

    # cocotb's runner overwrites PYTHONPATH rather than extending it
    # (`_set_env_common()` ends with `self.env["PYTHONPATH"] =
    # os.pathsep.join(sys.path)`, after `self.env = dict(extra_env)`), so
    # extra_env["PYTHONPATH"] is silently discarded. The golden model and the
    # testbench directory therefore go on this process's sys.path. A wrong
    # path makes the suite not RUN (import error, exit 2) instead of failing.
    for path in (GOLDEN, test_dir):
        if str(path) not in sys.path:
            sys.path.insert(0, str(path))

    pythonpath = os.pathsep.join(
        [str(GOLDEN), str(test_dir)] + ([os.environ["PYTHONPATH"]] if os.environ.get("PYTHONPATH") else [])
    )

    try:
        results_xml = runner.test(
            hdl_toplevel=args.toplevel,
            test_module=args.test_module,
            test_dir=test_dir,
            build_dir=build_dir,
            seed=args.seed,
            timescale=TIMESCALE,
            testcase=args.testcase,
            waves=args.waves,
            extra_env={"PYTHONPATH": pythonpath, "PYTHONDONTWRITEBYTECODE": "1"},
            results_xml=str(build_dir / "results.xml"),
        )
    except Exception as exc:                      # simulator could not be launched
        print(f"{args.sim}: the simulator did not run: {exc}", file=sys.stderr)
        return EXIT_DID_NOT_RUN

    # cocotb's runner does NOT raise on a failing test -- it returns the
    # results XML and leaves the verdict to the caller. Reading it here is
    # what makes this script usable as a CI gate: without it, an injected-bug
    # run (see `--define INJECT_BUG_*`) would exit 0 with 11 failures, and a
    # green CI would mean nothing.
    #
    # The two non-zero exits are deliberately DIFFERENT, and callers are meant
    # to tell them apart: EXIT_FAILED means the suite ran and reported
    # failures, EXIT_DID_NOT_RUN means no verdict exists at all. A caller that
    # treats "non-zero" as "the testbench caught it" -- which is exactly what
    # a negative control does -- passes for the wrong reason when the suite
    # cannot start.
    # Count the tests that actually executed, not the XML entries: a test
    # cocotb skipped or filtered out with --testcase is not a pass (#130).
    try:
        executed, num_failed, num_skipped = count_executed(Path(results_xml))
    except (RuntimeError, OSError) as exc:
        print(f"{args.sim}: the suite produced no results: {exc}", file=sys.stderr)
        return EXIT_DID_NOT_RUN
    skipped_note = f", {num_skipped} skipped" if num_skipped else ""
    print(f"{args.sim}: {executed - num_failed}/{executed} passed{skipped_note}", file=sys.stderr)
    if executed == 0:
        if num_skipped:
            print(f"{args.sim}: no test executed -- {num_skipped} skipped "
                  "(filtered out by --testcase)", file=sys.stderr)
        else:
            print(f"{args.sim}: results XML contains no tests", file=sys.stderr)
        return EXIT_DID_NOT_RUN
    return EXIT_FAILED if num_failed else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
