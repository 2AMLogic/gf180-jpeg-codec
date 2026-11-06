#!/usr/bin/env python3
"""Zero-delay gate-level run of the top-level smoke bench (issue #89).

Runs the unchanged verification/rtl/test_top_smoke.py against the committed
synthesized netlist flow/netlist/jpeg_codec_top_synth.v instead of rtl/*.v.
The sources are: that netlist, the PDK standard-cell Verilog models of the
library the netlist is mapped to (derived from the netlist, not hardcoded),
the PDK primitives, and verification/rtl/sram_macro_model.v for the macro
(the netlist leaves gf180_sram_256x32 as a black box). No hand-written cell
models. No SDF: this is the zero-delay run; #36 adds timing.

The PDK comes from flow/pdk.env, which refuses a tree whose open_pdks revision
differs from the pin; this script fails (exit 2, before simulating) when it
does.

    python3 verification/rtl/run_top_smoke_gl.py                 # run_tb path
    python3 verification/rtl/run_top_smoke_gl.py --inject-fault  # expect exit 1
    python3 verification/rtl/run_top_smoke_gl.py --test-module test_top_golden
        # the byte-exact golden suite instead of the smoke bench (issue #102)
    python3 verification/rtl/run_top_smoke_gl.py --klt-request OUTDIR
        # write OUTDIR/request.json and OUTDIR/netlist.sha256, for
        #   klt functional-verification OUTDIR/request.json -o OUTDIR/run

Exit status as verification/common/run_tb.py: 0 pass, 1 a test failed, 2 the
suite did not run (including a PDK pin mismatch or a missing source).
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))
sys.path.insert(0, str(ROOT / "verification" / "golden"))

NETLIST = ROOT / "flow" / "netlist" / "jpeg_codec_top_synth.v"
PDK_ENV = ROOT / "flow" / "pdk.env"
MACRO_MODEL = HERE / "sram_macro_model.v"
TOPLEVEL = "jpeg_codec_top"
TEST_MODULES = ("test_top_smoke", "test_top_golden")

EXIT_DID_NOT_RUN = 2


class SetupError(Exception):
    """The run cannot start; maps to exit 2, never to a test verdict."""


def resolve_pdk() -> dict:
    """Source flow/pdk.env (which enforces the open_pdks pin) and return it."""
    out = subprocess.run(
        ["bash", "-c", f'. "{PDK_ENV}" >&2 && printf "%s\\n%s\\n%s" "$PDK_ROOT" "$PDK" "$OPEN_PDKS_REV"'],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise SetupError(f"PDK pin check failed: {out.stderr.strip()}")
    pdk_root, pdk, rev = out.stdout.split("\n")
    return {"PDK_ROOT": pdk_root, "PDK": pdk, "OPEN_PDKS_REV": rev}


def netlist_library(netlist: Path) -> str:
    """The standard-cell library the netlist instantiates (must be exactly one)."""
    libs = set(re.findall(r"\bgf180mcu_fd_sc_(mcu\d+t\d+v\d+)__", netlist.read_text()))
    if len(libs) != 1:
        raise SetupError(f"{netlist} instantiates {sorted(libs) or 'no'} gf180mcu_fd_sc libraries, expected one")
    return f"gf180mcu_fd_sc_{libs.pop()}"


def sources(netlist: Path) -> tuple[list[Path], dict]:
    pdk = resolve_pdk()
    lib = netlist_library(netlist)
    vdir = Path(pdk["PDK_ROOT"]) / pdk["PDK"] / "libs.ref" / lib / "verilog"
    srcs = [netlist, vdir / f"{lib}.v", vdir / "primitives.v", MACRO_MODEL]
    for s in srcs:
        if not s.is_file():
            raise SetupError(f"missing source {s}")
    return srcs, {**pdk, "library": lib, "netlist_sha256": hashlib.sha256(netlist.read_bytes()).hexdigest()}


def faulty_netlist(tmp: Path) -> Path:
    """A copy of the netlist with every xor2_1 turned into or2_1 (negative control)."""
    text = NETLIST.read_text()
    lib = netlist_library(NETLIST)
    old, new = f"{lib}__xor2_1 ", f"{lib}__or2_1 "
    if old not in text:
        raise SetupError(f"no {old.strip()} instance to corrupt")
    path = tmp / NETLIST.name
    path.write_text(text.replace(old, new))
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inject-fault", action="store_true", help="negative control: corrupt a temp copy of the netlist; expect exit 1")
    ap.add_argument("--klt-request", metavar="OUTDIR", help="write a klt functional-verification request instead of running")
    ap.add_argument("--test-module", choices=TEST_MODULES, default="test_top_smoke", help="cocotb module to run against the netlist (default: test_top_smoke)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--testcase", default=None, help="comma-separated test names to run (default: all)")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        try:
            netlist = faulty_netlist(Path(tmp)) if args.inject_fault else NETLIST
            srcs, info = sources(netlist)
        except SetupError as exc:
            print(f"run_top_smoke_gl: {exc}", file=sys.stderr)
            return EXIT_DID_NOT_RUN
        info["netlist"] = str(NETLIST.relative_to(ROOT))
        if args.inject_fault:
            info["fault_injected"] = "every xor2_1 instance replaced by or2_1 in a temp copy"
        print(json.dumps(info, indent=2), file=sys.stderr)

        if args.klt_request:
            out = Path(args.klt_request)
            out.mkdir(parents=True, exist_ok=True)
            request = {
                "sources": [str(s) for s in srcs],
                "hdl_toplevel": TOPLEVEL,
                "engine": "icarus",
                "testbench": {"module": args.test_module, "search_path": str(HERE)},
                "options": {
                    "timescale": ["1ns", "1ps"],
                    "random_seed": args.seed,
                    "includes": [str(ROOT / "rtl")],
                },
            }
            if args.testcase:
                request["testbench"]["testcase"] = args.testcase.split(",")
            (out / "request.json").write_text(json.dumps(request, indent=2) + "\n")
            (out / "netlist.sha256").write_text(f"{info['netlist_sha256']}  {info['netlist']}\n")
            return 0

        import run_tb  # noqa: E402

        run_tb.TB = HERE
        run_tb.SOURCES = srcs
        run_tb.TOPLEVEL = TOPLEVEL
        run_tb.TEST_MODULE = args.test_module
        extra = ["--testcase", args.testcase] if args.testcase else []
        return run_tb.main(["--seed", str(args.seed)] + extra)


if __name__ == "__main__":
    sys.exit(main())
