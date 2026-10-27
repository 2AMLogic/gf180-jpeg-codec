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

## Configuration / table-load / header bench (`verification/rtl/`)

`verification/rtl/test_config_header.py` drives `jc_cfg_regs`, `jc_table_load`,
`jc_header_gen` and `jc_out_mux` (top `tb_config_top.v`) with two
`sram_rw_model.v` instances for M1/M2. `sram_model.v` has no write client port,
so a read/write model with the same A = 2 timing is used here. Oracles are
written from spec sections 7, 8 and T.81 Annex C, not from the RTL or the
golden framing code.

```sh
python3 verification/rtl/run_config_header.py      # icarus; same exit codes as run_tb.py
python3 verification/rtl/gen_table_rom.py --check  # rtl/jc_table_load_rom.v is current
```

Covers: Annex K reset load (busy until done) and its header, colour/grey/QOI
headers at sizes 1 and 65535, every rejection rule (`ZERO_QUANT`,
`BAD_HUFFMAN` variants, `BAD_CONFIG`, `ADDR_UNMAPPED`, `TABLE_INVALID`),
writes while busy, canonical codes (16-bit code, chain tables, random valid
tables) against an independent Annex C computation, partial commits, and random
memory and output stalls. Not covered: cycle budgets, the golden comparison
(#34). Note the spec section 7 figure 625 B includes `EOI`: the header is 623 B.

## QOI stage bench (`verification/rtl/`)

`verification/rtl/test_qoi.py` drives `jc_qoi` (RTL: `rtl/jc_qoi.v`) on
`sram_model_rw.v`, an M0 model with a write port and the record 0005 A = 2
timing (`tb_qoi_top.v`). `jc_qoi` emits the chunk stream only, so each image
is compared byte for byte with `qoi_golden.qoi_encode(...)[14:-8]`; one test
adds the header and end marker and decodes the result with the vendored
`qoi.h` (`qoi_dec_ref.c`, needs a C compiler).

```sh
python3 verification/rtl/run_qoi.py                # icarus; same exit codes as run_tb.py
```

Covers: six image classes (flat, gradient, noise, runs, index hits, DIFF/LUMA
edges), 1-pixel images, runs of 62/63, per-frame index clear with a poisoned
array and back-to-back frames, out_ready/input/M0 back-pressure, and cycles
per pixel on `noise_64x48` (seed 7), whole frame and steady state, against
5.43 (spec §8) and 4 (record 0005 §7). Simulated cycles, not measurements.

## Top-level smoke bench (issue #48)

`verification/rtl/test_top_smoke.py` drives `jpeg_codec_top` (all of `rtl/`
except the placeholder) with `sram_macro_model.v`, a pin-accurate model of the
`gf180-sram` 256 x 32 macro (`CEN`/`GWEN` active low, per-bit `WEN`, one-cycle
read latency). It configures the chip through the configuration port, feeds
block-ordered pixels, and checks: colour (32 x 16, and 20 x 18 with host edge
padding) and grey (16 x 8) output decodes in Pillow 10.2.0 without warning and
has the right size; QOI (12 x 9) decodes with `qoi.h`; and, as a stronger
check than the issue asks for, every output is byte-identical to the golden
encoder (the full item-5 comparison is #34). One colour case runs with
random input and output stalls. Needs cocotb 2.1.0, Pillow 10.2.0 and a C
compiler.

```sh
python3 verification/rtl/run_top_smoke.py          # icarus; same exit codes as run_tb.py
```
