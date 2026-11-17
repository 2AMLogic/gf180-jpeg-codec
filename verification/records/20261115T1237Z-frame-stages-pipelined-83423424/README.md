# The pipelined `jc_huff` symbol path re-count at 640 x 480, colour 4:2:0 — issue #137

Issue #137's RTL remedy for the q95 gap record 0008 documented: `rtl/jc_huff.v`'s
four-state blocking FSM (every symbol serialized behind its table round trip,
≥4 cycles plus 1 per in-run zero) is replaced by a pipelined symbol path
(decision record `spec/decision-records/0009-huff-symbol-path-pipelining.md`)
issuing one lookup per two cycles — the A = 2 grant cadence of the shared
memory port. This record re-counts the three rows of
`verification/rtl/test_top_frame_cycles.py` on that RTL. All figures are
**simulated**, never measured (spec §9, CLAUDE.md).

Provenance: bench, RTL and `sram_macro_model.v` at commit `83423424` (branch
`feature/issue-137`). Same seed (1), same images, same driver as
`20261115T0046Z-frame-stages-61644ee`; every generated image was
sha256-checked against `verification/images/SHA256SUMS` before encoding
(`load_image`, shared with `test_top_golden.py`); the pixel stream was
exactly 921,600 bytes (1200 MCUs x 768) and `status_error` was 0 at the end
of each frame.

## Headline result: the q95 row is inside the §9 period

| Row | cycles to `out_last` (was, record 0008) | % of 1,666,667 period | frames/s simulated | output bytes | `golden_match` |
|---|---|---|---|---|---|
| `scene_fbm` q50 | **982,462** (982,471) | 58.9% | 50.9 | 18,616 | true |
| `noise_max_entropy` q50 | **982,464** (1,103,167) | 58.9% (was 66.2%) | 50.9 | 126,543 | true |
| `noise_max_entropy` q95 | **1,088,887** (1,740,070) | **65.3%** (was 104.4%) | **45.9** (was 28.7) | 360,997 | true |

- The q95 row is **1.53x inside the frame period** — the §9 target row is
  met at the quality the blocking FSM missed. Output byte counts are
  unchanged on all three rows and every row is byte-identical to
  `jpeg_golden.encode`: the change is scheduling-only, as record 0009 argues.
- Both q50 rows improve or hold: `scene_fbm` is 9 cycles faster (drift-level),
  `noise_max_entropy` q50 improves by 120,703 cycles because the blocking FSM
  bound that row too (909.9 cycles/MCU of FSM floor) and now does not.
- Per-row `fraction_of_frame_period` and `cycles_to_status_idle` are in
  `cycles.json` (`schema_version` 2, unchanged bench); the sampler window
  identity (`stage_sample_cycles` = the integer edge count between frame
  start and the `out_last` beat) holds on every row.

## Where the cycles went

Stalled cycles per boundary (`valid && !ready`), per row — with the old
record's values in parentheses:

| Boundary (producer → consumer) | `scene_fbm` q50 | `noise_max_entropy` q50 | `noise_max_entropy` q95 |
|---|---|---|---|
| `pix` (host → jc_downsample) | 59,995 (59,995) | 59,995 (180,233) | 165,995 (815,795) |
| `s2` (jc_downsample → jc_mb_ctrl) | 51,589 (51,589) | 51,589 (170,534) | 156,114 (801,864) |
| `s3` (jc_mb_ctrl → jc_dct) | **636,019** (636,019) | **636,019** (895,642) | **882,354** (1,545,304) |
| `s4` (jc_dct → jc_zigzag) | 0 (0) | 0 (180,585) | 166,278 (817,231) |
| `s5` (jc_zigzag → jc_quant) | 57,877 (108,350) | 316,181 (637,856) | 627,115 (1,278,299) |
| `s6` (jc_quant → jc_huff) | 11,334 (79,550) | 103,372 (610,671) | 352,388 (1,268,261) |
| `s7` (jc_huff → jc_bitpack) | 0 (0) | 45 (0) | 3,624 (9) |
| `bp` (jc_bitpack → jc_out_mux) | 0 (0) | 0 (0) | 0 (0) |
| `out` (jc_out_mux → host) | 0 (0) | 0 (0) | 0 (0) |

The binding stage at every row is now **stage 2, the DCT** (`s3` stalled
636,019 / 636,019 / 882,354) — exactly what record 0005 §7's slowest-stage
model and record 0009's corrected budget predict once stage 4 falls below
the input row. `jc_huff`'s own q95 window, counted-derived from the record's
components, is `2 x 425,695` symbols + `hf_m1` arbitration waits 39,211 +
`s7` back-pressure 3,624 = 894,225 cycles = **745.2 cycles/MCU**, below the
768-cycle input row: stage 4 has stopped binding at any content or quality,
which is the goal band (≤ 2.08 cycles/symbol) of record 0009's threshold
table. The unit-level sustained rate is counted directly by
`test_entropy.py::test_throughput`: **2.000 cycles/symbol** (6141 cycles
over 3071 symbol intervals of fully dense blocks, byte-exact against the
spec §6 reference).

The AC's literal frame ratio, stated for the record: `cycles_to_out_last` ÷
425,695 = **2.558** at q95. That ratio's mechanical floor is 921,600 ÷
425,695 = 2.165 (the input-bus row alone) for *any* implementation, so it
cannot reach the ≤ 2.08 threshold; the thresholds are defined on the stage's
own window and are evaluated there (above). The target outcome record 0009's
corrected model describes — frame 1,012,868 with `jc_huff` below the input
row — reads 2.379 on the same ratio.

## The predicted `qa` contention materialized (reported, not treated)

Arbitration-request stalls (`req && !gnt`), per row — old record's values in
parentheses:

| Pair | `scene_fbm` q50 | `noise_max_entropy` q50 | `noise_max_entropy` q95 |
|---|---|---|---|
| `hf_m1` (jc_huff on M1) | 8,002 (221) | 29,569 (3,050) | 39,211 (9) |
| `hf_m2` (jc_huff on M2) | 0 (0) | 0 (0) | 0 (0) |
| `qa` (quantizer holder on M1) | 20,276 (17,118) | 250,761 (36,383) | **407,647** (4,826) |

With `jc_huff` issuing one M1 lookup per two cycles, the quantizer's Q-word
holder — outranked by `jc_huff` in `u_arb1` — waits far longer than before:
`qa` stalls 407,647 cycles at q95 (4,826 before). The wait bleeds into
S5/S6 latency and the q95 frame sits ~76,000 cycles above record 0009's
derived stage-2 model row (1,012,661): exactly the effect record 0009's
evidence section flagged as a legitimate outcome to report, not a regression
— §9 is met with 1.53x margin, and the `qa` shift is a load moved into
stage 3's slack. `m1_en` occupancy is 411,326 cycles (342.8/MCU) and `m2_en`
129,705 at q95 — the M1/M2 port rows of record 0005 §7 stay loose. Any
future M1 traffic added on top of `jc_huff`'s new rate must re-derive this
interaction together with §7's occupancy rows (record 0009, Consequences).

## Accounting closure and non-intrusiveness

For every boundary and row, stalled + starved + transferred + idle =
`stage_sample_cycles`; `pix.transferred` = 921,600 (the pixel stream) and
`out.transferred` = `output_bytes` on every row, cross-checking the sampler
against the byte-collecting monitors. `cycles_to_status_idle` is `out_last`
+ 2 cycles on every row (the blocking FSM's +2 shape is preserved). The q95
row decodes in Pillow 10.2.0 at (640, 480), mode RGB, warnings fatal.

## Tools, host and wall time

- Icarus Verilog **13.0** (stable), cocotb **2.1.0**, Pillow **10.2.0**,
  CPython **3.12.3**, seed 1 — same versions as the record 0008 count.
- The three-row bench run: `FRAME_CYCLES_JSON=... python3
  verification/rtl/run_stage.py top_golden --test-module
  test_top_frame_cycles` (~9.5 min wall on the shared 8-vCPU worker; per-row
  `wall_time_s` in `cycles.json`).
- klt **0.8.0** (`klayout-tools[functional-verification]==0.8.0`) re-ran the
  same three rows through `klt functional-verification` for `report.json`,
  in a throwaway `uvx` environment — the host toolchain was not modified.
  `report.json` carries the same cycle/byte figures line for line.
- Not split: one cocotb process per run, three tests, sequential. RTL
  digital simulation; no batch fleet involved. **Not added to any CI or
  required job.**

## Reproducing (cold start)

```sh
bash .github/scripts/install-oss-cad-suite.sh      # -> ~/oss-cad-suite
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install 'cocotb==2.1.0' 'pillow==10.2.0'

# from the repository root; exit 0 = all rows pass, 1 = a row failed,
# 2 = the suite did not run
FRAME_CYCLES_JSON=$PWD/cycles.json \
  python3 verification/rtl/run_stage.py top_golden --test-module test_top_frame_cycles
```

The klt route that produced `report.json` (paths in `request.json` are
repository-root-relative; feed the request on stdin from the repository
root):

```sh
PYTHONPATH=verification/golden:verification/rtl \
uvx --python 3.12 --from "klayout-tools[functional-verification]==0.8.0" \
    --with "cocotb==2.1.0" --with "pillow==10.2.0" \
    klt functional-verification - -o <outdir> --format json \
    < verification/records/20261115T1237Z-frame-stages-pipelined-83423424/request.json \
    > report.json
# klt: 0 every test passed, 3 a test failed, 1 request/environment error
```

Both routes are deterministic at seed 1. `cycles.json` is written by the
bench itself (`_write_rows`, `schema_version` 2); this record is append-only
and quotes the committed JSON rather than a hand-transcribed log line.

## Where the decision went

Decision record `spec/decision-records/0009-huff-symbol-path-pipelining.md`
records the remedy, the re-derived §7 row 4 (745.2 cycles/MCU at q95, the
re-derived "Slowest stage" and "Frame bound" paragraphs of record 0005 §7),
the byte-exactness argument, and the combined frame figure at both of
`0007-pre-route-setup-shortfall.md` §4's depths. The q95 shortfall record
0008 documented is closed; §9's ratified target row is unchanged.
