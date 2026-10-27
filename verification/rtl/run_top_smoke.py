#!/usr/bin/env python3
"""Runs the top-level smoke bench (jpeg_codec_top with the macro model).

Reuses the vendored runner in verification/common/run_tb.py with the whole
RTL tree as sources; its flags and exit statuses are unchanged (0 pass, 1 a
test failed, 2 the suite did not run).

    python3 verification/rtl/run_top_smoke.py                  # icarus
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))
sys.path.insert(0, str(ROOT / "verification" / "golden"))

import run_tb  # noqa: E402

run_tb.TB = HERE
run_tb.SOURCES = sorted(
    p for p in (ROOT / "rtl").glob("*.v") if p.name != "smoke_placeholder.v"
) + [HERE / "sram_macro_model.v"]
run_tb.TOPLEVEL = "jpeg_codec_top"
run_tb.TEST_MODULE = "test_top_smoke"

if __name__ == "__main__":
    sys.exit(run_tb.main())
