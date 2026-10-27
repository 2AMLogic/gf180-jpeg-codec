# verification

cocotb benches, driven through the runner vendored from
`2AMLogic/gf180-polysynth` (pinned in `/reuse.lock.json`; divergences in
`spec/decision-records/0001-harness-divergence.md`).

## Simulator versions

The pinned toolchain is Icarus Verilog 14.0 and Verilator 5.053 (OSS CAD Suite
2026-09-16), with cocotb 2.1.0. Ubuntu's apt Verilator cannot build cocotb
2.1's shim, so do not use it.

## Cold start

```sh
bash .github/scripts/install-oss-cad-suite.sh      # -> ~/oss-cad-suite
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install cocotb==2.1.0

python3 verification/common/run_tb.py --sim icarus
python3 verification/common/run_tb.py --sim verilator
bash verification/tb/negative_control.sh           # injected bug must exit exactly 1
bash .github/scripts/lint.sh
```

`run_tb.py` exit status: `0` all tests passed, `1` the suite ran and a test
failed, `2` the suite did not run (build error, import error, empty results).
A negative control must require exactly `1`.

`verification/tb/test_smoke.py` drives `rtl/smoke_placeholder.v`, a stand-in
that is not the codec.

## Status

The skeleton was run here on Icarus 13.0 and Verilator 5.050 (host versions),
not the pinned 14.0 / 5.053.

## Golden JPEG model and libjpeg cross-check

`verification/golden/jpeg_golden.py` is the integer-only, stdlib-only golden
encoder (spec §11, record 0003). From the repo root:

```sh
python3 -m unittest discover -s verification/golden -p 'test_*.py'
python3 verification/golden/crosscheck_libjpeg.py                   # needs Pillow 10.2.0
python3 verification/golden/crosscheck_libjpeg.py --negative-control  # must exit exactly 1
```

The cross-check decodes every golden file in Pillow and compares its
entropy-coded segment with libjpeg-turbo's, for 64 x 48 and 16 x 16 images at
qualities 10, 50, 75 and 95, colour 4:2:0 and grey. Exit `0` all pass, `1` a
case failed, `2` it did not run (Pillow missing or not 10.2.0). Each normal run
appends one timestamped record under `verification/records/`; never edit or
delete an earlier one. The negative control writes none.

## Entropy stage bench (`verification/rtl/`)

`verification/rtl/test_entropy.py` drives `jc_zigzag -> jc_huff -> jc_bitpack`
(RTL: `rtl/jc_*.v`, ports per decision record 0005) with two `sram_model.v`
instances standing in for M1/M2 and a pass-through stand-in for the quantizer
(`tb_entropy_top.v`). Its integer reference is written from spec section 6
only; Annex K table data comes from the golden module, the worked-example
bytes are pinned in the test.

```sh
python3 verification/rtl/run_entropy.py            # icarus; same exit codes as run_tb.py
```

Covers: the section 6 worked example (12 bytes), all-zero block, position 63
non-zero, ZRL runs, `FF 00` stuffing, DC chain across components and frames,
size-10 AC and size-11 DC, output/input/memory back-pressure, and 600 seeded
random blocks. Not covered here: cycle counts against the record 0005 budget
rows, and the byte-exact comparison with the golden encoder (#34).
