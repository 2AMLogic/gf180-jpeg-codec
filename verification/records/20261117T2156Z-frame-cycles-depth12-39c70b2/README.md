# The depth-12 frame re-count at 640 x 480, colour 4:2:0 — issue #197

Record 0009's counted rows (1,088,887 cycles to `out_last` at q95, 65.3% of
the §9 period) were produced at DCT depth 8, before the depth-12 `jc_dct1d`
retiming (record 0007 §4's band edge) merged; at the tree as merged the only
counted figure in the records was a Judge-side run quoted on PR #152
(1,383,370 cycles), not committed evidence. This record is that re-count,
committed on the merged tree, so the headline §9 figure rests on append-only
evidence again. All figures are **simulated**, never measured (spec §9,
CLAUDE.md).

## Result

Testbench `verification/rtl/test_top_frame_cycles.py` (launched as
`python3 verification/rtl/run_stage.py top_golden --test-module
test_top_frame_cycles`, the documented one way to launch every bench; runner
exit 0, **3/3 pass**), three rows, colour 4:2:0 at 640 x 480 (exactly 1200
MCUs, no host padding). Machine-written figures are in `cycles.json`; the
bench's `"issue": 119` field inside it is the schema-2 stage-counter
provenance and stays as the bench wrote it — this run is issue #197's.
Cycle counts are machine-written and exact to ±1 as this bench computes
them (position-dependent within a simulation — see "Disposition of the
quoted 1,383,370" below); the rounded percentages and frame rates are
unaffected.

| Image | Quality | Output bytes | Cycles to `out_last` | % of frame period (1,666,667) | % of record 0005 bound (1,503,668) | Byte-exact vs golden |
|---|---|---|---|---|---|---|
| `scene_fbm` | 50 | 18,616 | **1,383,316** | 83.0 | 92.0 | yes |
| `noise_max_entropy` | 50 | 126,543 | **1,383,318** | 83.0 | 92.0 | yes |
| `noise_max_entropy` | 95 | 360,997 | **1,383,369** | **83.0** | **92.0** | yes |

Every row is inside the §9 floor/ceiling band (921,600 – 1,666,667 cycles)
with `golden_match` true, and the byte counts equal the depth-8 re-count's
(18,616 / 126,543 / 360,997) — the depth-12 retiming moves cycles, not
bytes. Derived frame rates at the §9 signoff clock of 50 MHz
(`50e6 / cycles per frame`, **simulated**, never measured): **36.1 frames/s**
on every row (36.145 at q50, 36.144 at q95) against the 30 frames/s target —
a 1.20x margin, §9 met.

## Provenance

Bench, RTL and sources at commit `39c70b2` (branch `feature/issue-197`, the
tree as merged from PRs #152 and #200 — `rtl/jc_dct1d.v` at 12 cycles per
vector, `test_top_frame_cycles.py` importing `REG_CMD` from `cfg_host`, the
#194 fix). Same seed (1), same images, same driver as
`20261115T1237Z-frame-stages-pipelined-83423424`; every generated image was
sha256-checked against `verification/images/SHA256SUMS` before encoding
(`load_image`, shared with `test_top_golden.py`), the pixel stream was
exactly 921,600 bytes (1200 MCUs x 768), and `status_error` was 0 at the end
of each frame. Wall time 267.7 / 273.6 / 290.5 s per row.

Environment, disclosed: Icarus Verilog **13.0** (the same engine version the
depth-8 re-count's report records) with cocotb **2.1.0** and Pillow **10.2.0**
for the decode cross-check, in a throwaway venv, on a shared dispatch host —
one local `run_stage.py` invocation, no parallel fan-out. This is not the
README-pinned OSS CAD Suite 14.0 toolchain; the figures are labelled
simulated and cite the engine they came from.

## Disposition of the quoted 1,383,370

The provenance paragraphs of record 0005 §7 and record 0009 quote a
Judge-side run on PR #152 giving **1,383,370** cycles to `out_last`; the PR
#200 evaluation later reported the restored bench giving **1,383,369**, one
cycle lower, and this record's committed q95 count is that lower reading
(1,383,369, third test in the simulation). Re-running this bench with the
q95 row first (at the PR head `e89c1bb`, whose only RTL delta from the
recorded `39c70b2` is comment-only in `jc_quant.v`; same seed, same engine)
writes **1,383,370** for the same frame — so the two quoted
figures are the **same beat** read through a floor-sensitive timestamp, not
two counters disagreeing and not variance in the RTL. Every residue-free
counter is identical across positions: the edge-counted stage-sampler
window (1,383,370 edges over 13,833,690.000 ns at q95, 1,383,316 edges over
13,833,150.000 ns at q50), `drive_cycles` (1,383,371 / 1,383,317), all nine
stages' four `stage_counts`, the arbiter and SRAM occupancy counters,
`output_bytes`, and `golden_match`. As this bench computes it —
`cycles_to_out_last` floors a nanosecond timestamp rather than counting
edges (filed as #208) — the figure is exact to **±1**, and the ±1 is
**positional**, not a per-row property: the `stage_sample_window_ns` starts
in this run's `cycles.json` (32760.000, 13898700.001, 27764670.002 ns)
accumulate a sub-nanosecond residue per preceding test, and
`stage_sample_cycles` − `cycles_to_out_last` follows the same order — 0 on
the first test of a simulation, +1 on any later one (`scene_fbm` q50 here
ran first and reproduces exactly; the `noise_max_entropy` rows ran later
and carry the +1). The operative statement for the merged tree is therefore
the **1,383,369 / 1,383,370 pair over the residue-free counters above**,
not a single exact count; both quoted transcriptions sit inside that pair,
and the records citing this count (`0005` §7, `0009`, `0013`) carry the ±1
resolution. The rounded §9 figures — 83.0% of the period, 92.0% of the
0005 bound, 36.1 frames/s simulated — are unchanged under this resolution.

## Counted vs the derived depth-12 row

Record 0009's depth-12 row is derived, not counted: 1,473,851 cycles (88.4%
of the period), built from 1200 x the 1224-cycle stage-2 row plus first-MCU
latency and the header. The counted frames land below it (1,383,316 –
1,383,369, 83.0%): the derivation is a bound-style estimate, and the real
DCT's per-MCU cost on this content is lower than the 1224-cycle band-edge
row. The derivation tables are untouched (that is record 0007 §4's material);
the §9 verdict is unchanged either way — met at 83.0% counted, met at 88.4%
derived.
