# Cycles per frame at 640 x 480, colour 4:2:0 — issue #113

`spec/codec.md` §9 requires that any frame-rate figure be derived as
`signoff clock / cycles per frame`, with cycles per frame **counted in
simulation** on a named §12 image (`noise_max_entropy_640x480` the worst case,
`scene_fbm_640x480` the typical case). Nothing committed held that count:
decision record 0005 §7 gives a derived bound (1,503,668 cycles, 90.2% of the
1,666,667-cycle frame period at 50 MHz and 30 frames/s) and says itself that
it is a budget, not a result, and the 180-case golden suite runs only at
64 x 48 and 16 x 16 with cycle counts explicitly not a result. This record is
that count.

**Every figure here is simulated, never measured.** It is an RTL cocotb run of
`jpeg_codec_top` with `sram_macro_model.v` under Icarus, with no host stalls.
There is no silicon and no board behind any number on this page.

## Result

Testbench `verification/rtl/test_top_frame_cycles.py`, three rows, colour
4:2:0 at 640 x 480 (exactly 1200 MCUs, so no host padding). Machine-written
figures are in `cycles.json`; the klt verdict is in `report.json`.

| Image | Quality | Output bytes | Cycles to `out_last` | Cycles/MCU | % of frame period (1,666,667) | % of record 0005 bound (1,503,668) | Byte-exact vs golden |
|---|---|---|---|---|---|---|---|
| `scene_fbm` | 50 | 18,616 | **982,471** | 818.73 | 58.9 | 65.3 | yes |
| `noise_max_entropy` | 50 | 126,543 | **1,103,167** | 919.31 | 66.2 | 73.4 | yes |
| `noise_max_entropy` | 95 | 360,997 | **1,740,070** | 1450.06 | **104.4** | 115.7 | yes |

Derived frame rates at the §9 target signoff clock of 50 MHz
(`50e6 / cycles per frame`, **simulated**, never measured):

| Image | Quality | Simulated frames/s | §9 target row (30 frames/s) |
|---|---|---|---|
| `scene_fbm` | 50 | 50.9 | met, 1.70x margin |
| `noise_max_entropy` | 50 | 45.3 | met, 1.51x margin |
| `noise_max_entropy` | 95 | 28.7 | **not met**, 0.96x — see Finding below |

### Two reference points, and which one is the result

The figure above is **frame start to the `out_last` beat**, which is what §9
asks for. The driver's `Host.cycles` in `test_top_smoke.py` is frame start to
`status_idle`, a strict superset: `out_monitor` there sets `last_seen` on the
`out_last` beat but takes no timestamp, and `run_frame` computes `cycles` only
after `wait_idle()`. Reusing it would report a number slightly larger than
this record claims. Measured difference on all three rows: **2 cycles**
(`cycles_to_status_idle` in `cycles.json`). Small, but it is the difference
between the figure §9 names and a different figure, so the bench timestamps
the `out_last` beat itself and both numbers are recorded.

### What each row also checked

- The generated PPM's sha256 matched `verification/images/SHA256SUMS` before
  it was encoded (`load_image`, shared with `test_top_golden.py`).
- No host stalls, enforced rather than assumed: `out_ready` held at 1 for the
  whole run and `pix_valid` held at 1 until the last pixel byte was accepted
  (`out_ready_stall_cycles` and `pix_valid_gap_cycles` are 0 on every row).
- The pixel stream was exactly 921,600 bytes (1200 MCUs x 768), and
  `status_error` was 0 at the end of each frame.
- The output decoded in Pillow 10.2.0 with `warnings.simplefilter("error")`
  at size (640, 480), mode RGB — an independent check, never a substitute for
  byte-exactness.
- The output was byte-identical to `jpeg_golden.encode` on all three rows. The
  byte counts also agree with an independent run of the golden encoder alone
  (18,616 / 126,543 / 360,997).

## Finding: the q95 worst-case row exceeds the frame period

`noise_max_entropy_640x480` at **quality 95** takes **1,740,070 cycles**,
which is **104.4%** of the 1,666,667-cycle frame period and **115.7%** of
record 0005 §7's derived bound — 1450.06 cycles/MCU against the §9 budget of
1388.9. At 50 MHz that is 28.7 frames/s simulated, not 30.

This is recorded and filed as a finding (issue #119), **not** tuned away: the
bench asserts the mechanical range [921,600, 1,666,667] and fails on this row,
so `report.json` is `status: fail` with 2 of 3 passing. No cycle budget, spec
row or golden model was adjusted, and the assertion was written before the
figure was known.

Scope of the finding, stated precisely:

- The §9 **target row is met** at the reset-default quality 50 on both images
  §9 names, with 1.5x to 1.7x margin. §9 pins the images, not the quality.
- It is **not met** at quality 95 on the worst-case image. q95 is a legal
  configuration of the ratified spec (`spec/codec.md` §5 host-scaled Annex K),
  so the gap is real and belongs in the tracker, not in a footnote.
- Record 0005 §7 predicted the binding stage at worst-case content to be
  stage 5 (bit pack, 1249 cycles/MCU) on the strength of the §3 per-block
  worst case of 1,248.75 bytes/MCU. The measured q95 output is 300.8
  bytes/MCU, 24% of that, so stage 5 is **not** the constraint here and
  1450.06 cycles/MCU is above every single-stage budget row in that table.
  Which stage actually binds is the finding's question, not this record's: no
  per-stage count was taken here.

## Tools, host and wall time

- Icarus Verilog **13.0** (stable) — note `verification/README.md` pins 14.0;
  the committed `top-golden-*` records were also run with 13.0 on this host.
- cocotb **2.1.0**, Pillow **10.2.0**, CPython **3.12.3**, seed 1.
- klt **0.8.0** (`klayout-tools[functional-verification]==0.8.0`) for
  `report.json`, run in a throwaway `uvx` environment on Python 3.12 — the
  host toolchain was not modified.
- Wall time, cocotb's own per-test real time on a shared 16-vCPU host:
  **157.7 s + 164.5 s + 173.5 s = 495.7 s (8 min 16 s)** for the three rows at
  load average ~7.5 (about 77,000 simulated ns per real second). The second,
  independent `klt` execution that produced `report.json` ran the same three
  rows in **99.5 s + 135.8 s + 165.5 s = 400.8 s (6 min 41 s)** on a quieter
  host — the spread between the two runs is host load, not a difference in the
  work. Per-row wall time is in `cycles.json` (`wall_time_s`) for the first and
  in `report.json` (`real_time_s`) for the second.
- Not split: one cocotb process, three tests, sequential. This is an RTL
  digital simulation, not a SPICE grid; no batch fleet was involved.
- **Not added to any CI or required job** — 8 minutes of simulator time per
  run does not belong in `ci.yml` or `signoff.yml`.

## Reproducing (cold start)

```sh
bash .github/scripts/install-oss-cad-suite.sh      # -> ~/oss-cad-suite
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install 'cocotb==2.1.0' 'pillow==10.2.0'

# from the repository root
FRAME_CYCLES_JSON=$PWD/cycles.json \
  python3 verification/rtl/run_top_golden.py --test-module test_top_frame_cycles
# exit 0 all rows in range, 1 a row failed (today: 1, see Finding), 2 did not run
```

`cycles.json` is written by the bench itself, one row appended per test, so the
table above quotes a machine-written number rather than a transcribed log line.

The `klt` route that produced `report.json`, from the repository root (paths in
`request.json` are repository-root-relative, so the request is fed on stdin and
resolves against the current directory):

```sh
PYTHONPATH=verification/golden:verification/rtl \
uvx --python 3.12 --from "klayout-tools[functional-verification]==0.8.0" \
    --with "cocotb==2.1.0" --with "pillow==10.2.0" \
    klt functional-verification - -o <outdir> --format json \
    < verification/records/20261114T0551Z-frame-cycles-62d88e1/request.json \
    > report.json
# klt: 0 every test passed, 3 a test failed (today: 3), 1 request/environment error
```

Both routes are deterministic at seed 1: the `cycles.json` written by the
`klt` run carried the same output byte counts, `out_last` cycles,
`status_idle` cycles and golden verdicts as the committed one, row for row.

`report.json` is committed exactly as klt 0.8.0 emitted it. That version
records the run's `results_xml` / `test_log` / `build_log` as absolute paths
into the throwaway `-o` directory; newer klt nulls them and carries a sha256
instead (compare `20261106T1803Z-golden-gl-e32b0e8/report.json`). Those three
fields are the only host-specific content in the file, and the verdict was not
hand-edited.

## Append-only

This record is evidence, not a working document: do not edit or delete it.
A later run goes in a new directory.
