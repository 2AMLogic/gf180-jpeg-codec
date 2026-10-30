#!/usr/bin/env python3
"""Runs one RTL-stage cocotb bench by name.

Reuses the vendored runner in verification/common/run_tb.py with the stage's
sources, top level and test module from STAGES; the remaining flags and the
exit statuses are unchanged (0 pass, 1 a test failed, 2 the suite did not run,
which includes an unknown stage name).

    python3 verification/rtl/run_stage.py qoi                  # icarus
    python3 verification/rtl/run_stage.py qoi --sim verilator
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))

import run_tb  # noqa: E402

RTL = ROOT / "rtl"

# stage -> (sources, toplevel, test module)
STAGES = {
    # colour_convert
    "colour": (
        [RTL / "colour_convert.v", HERE / "colour_tb_top.v"],
        "colour_tb_top",
        "test_colour",
    ),
    # configuration / table-load / header (issue #46)
    "config_header": (
        [
            RTL / "jc_cfg_regs.v",
            RTL / "jc_table_load_rom.v",
            RTL / "jc_table_load.v",
            RTL / "jc_header_gen.v",
            RTL / "jc_out_mux.v",
            HERE / "sram_model.v",
            HERE / "tb_config_top.v",
        ],
        "tb_config_top",
        "test_config_header",
    ),
    # jc_zigzag, jc_huff, jc_bitpack
    "entropy": (
        [
            RTL / "jc_zigzag.v",
            RTL / "jc_huff.v",
            RTL / "jc_bitpack.v",
            HERE / "sram_model.v",
            HERE / "tb_entropy_top.v",
        ],
        "tb_entropy_top",
        "test_entropy",
    ),
    # jc_qoi on an M0 model
    "qoi": (
        [RTL / "jc_qoi.v", HERE / "sram_model.v", HERE / "tb_qoi_top.v"],
        "tb_qoi_top",
        "test_qoi",
    ),
}


def main(argv):
    if not argv or argv[0] not in STAGES:
        print(f"usage: run_stage.py {{{','.join(STAGES)}}} [run_tb.py flags]", file=sys.stderr)
        return 2
    run_tb.TB = HERE
    run_tb.SOURCES, run_tb.TOPLEVEL, run_tb.TEST_MODULE = STAGES[argv[0]]
    return run_tb.main(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
