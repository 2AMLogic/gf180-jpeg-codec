#!/usr/bin/env python3
"""Runs the entropy-stage cocotb bench (jc_zigzag, jc_huff, jc_bitpack).

Reuses the vendored runner in verification/common/run_tb.py with this stage's
sources, top level and test module; its flags and exit statuses are unchanged
(0 pass, 1 a test failed, 2 the suite did not run).

    python3 verification/rtl/run_entropy.py                  # icarus
    python3 verification/rtl/run_entropy.py --sim verilator
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))

import run_tb  # noqa: E402

run_tb.TB = HERE
run_tb.SOURCES = [
    ROOT / "rtl" / "jc_zigzag.v",
    ROOT / "rtl" / "jc_huff.v",
    ROOT / "rtl" / "jc_bitpack.v",
    HERE / "sram_model.v",
    HERE / "tb_entropy_top.v",
]
run_tb.TOPLEVEL = "tb_entropy_top"
run_tb.TEST_MODULE = "test_entropy"

if __name__ == "__main__":
    sys.exit(run_tb.main())
