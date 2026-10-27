#!/usr/bin/env python3
"""Runs the configuration / table-load / header bench (issue #46).

Reuses the vendored runner in verification/common/run_tb.py with this stage's
sources, top level and test module; flags and exit statuses are unchanged
(0 pass, 1 a test failed, 2 the suite did not run).

    python3 verification/rtl/run_config_header.py                  # icarus
    python3 verification/rtl/run_config_header.py --sim verilator
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))

import run_tb  # noqa: E402

run_tb.TB = HERE
run_tb.SOURCES = [
    ROOT / "rtl" / "jc_cfg_regs.v",
    ROOT / "rtl" / "jc_table_load_rom.v",
    ROOT / "rtl" / "jc_table_load.v",
    ROOT / "rtl" / "jc_header_gen.v",
    ROOT / "rtl" / "jc_out_mux.v",
    HERE / "sram_rw_model.v",
    HERE / "tb_config_top.v",
]
run_tb.TOPLEVEL = "tb_config_top"
run_tb.TEST_MODULE = "test_config_header"

if __name__ == "__main__":
    sys.exit(run_tb.main())
