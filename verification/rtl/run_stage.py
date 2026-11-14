#!/usr/bin/env python3
"""Runs one RTL cocotb bench by name.

Reuses the vendored runner in verification/common/run_tb.py with the bench's
sources, top level and test module from STAGES; the remaining flags and the
exit statuses are unchanged (0 pass, 1 a test failed, 2 the suite did not run,
which includes an unknown bench name).

    python3 verification/rtl/run_stage.py qoi                  # icarus
    python3 verification/rtl/run_stage.py qoi --sim verilator
    python3 verification/rtl/run_stage.py top_golden           # the byte-exact suite
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "verification" / "common"))
# The top-level benches reach the golden model (test_top_smoke.py imports
# jpeg_golden/qoi_golden). run_tb.main() puts GOLDEN on sys.path and on the
# simulator's PYTHONPATH itself, but only after the build, so keep the
# wrapper-side insert the per-bench run_top_*.py scripts used to carry.
sys.path.insert(0, str(ROOT / "verification" / "golden"))

import run_tb  # noqa: E402

RTL = ROOT / "rtl"

# Every .v in rtl/ plus the pin-accurate gf180-sram macro model: what the
# jpeg_codec_top benches build (issue #48).
TOP_SOURCES = sorted(RTL.glob("*.v")) + [HERE / "sram_macro_model.v"]

# stage -> (sources, toplevel, test module)
STAGES = {
    # colour_convert
    "colour": (
        [RTL / "colour_convert.v", HERE / "colour_tb_top.v"],
        "colour_tb_top",
        "test_colour",
    ),
    # jc_dct, jc_dct1d, jc_xpose_rf (issue #43)
    "dct": (
        [RTL / "jc_dct.v", RTL / "jc_dct1d.v", RTL / "jc_xpose_rf.v"],
        "jc_dct",
        "test_dct",
    ),
    # jc_quant, jc_quant_core (issue #44)
    "quantizer": (
        [RTL / "jc_quant.v", RTL / "jc_quant_core.v"],
        "jc_quant",
        "test_quantizer",
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
    # jpeg_codec_top smoke bench (issue #48)
    "top_smoke": (TOP_SOURCES, "jpeg_codec_top", "test_top_smoke"),
    # jpeg_codec_top byte-exact golden comparison (issue #88)
    "top_golden": (TOP_SOURCES, "jpeg_codec_top", "test_top_golden"),
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
