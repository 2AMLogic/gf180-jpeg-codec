#!/usr/bin/env python3
"""Runs the QOI-stage cocotb bench (jc_qoi on an M0 model).

Reuses the vendored runner in verification/common/run_tb.py with this stage's
sources, top level and test module; its flags and exit statuses are unchanged
(0 pass, 1 a test failed, 2 the suite did not run).

    python3 verification/rtl/run_qoi.py                  # icarus
    python3 verification/rtl/run_qoi.py --sim verilator
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))

import run_tb  # noqa: E402

run_tb.TB = HERE
run_tb.SOURCES = [
    ROOT / "rtl" / "jc_qoi.v",
    HERE / "sram_model_rw.v",
    HERE / "tb_qoi_top.v",
]
run_tb.TOPLEVEL = "tb_qoi_top"
run_tb.TEST_MODULE = "test_qoi"

if __name__ == "__main__":
    sys.exit(run_tb.main())
