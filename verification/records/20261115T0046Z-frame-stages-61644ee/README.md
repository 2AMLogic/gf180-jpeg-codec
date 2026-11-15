# Per-stage cycle attribution at 640 x 480, colour 4:2:0 — issue #119

Issue #119's finding: `noise_max_entropy_640x480` at quality 95 needs
1,740,070 cycles to `out_last` (record
`20261114T0551Z-frame-cycles-62d88e1`), 104.4% of the 1,666,667-cycle frame
period, and no per-stage count existed to say which stage binds. This record
is that count. The bench (`verification/rtl/test_top_frame_cycles.py`) gained
one sampler coroutine that classifies, per clock edge of the frame window
(frame start to the `out_last` beat, inclusive), every stage-boundary
handshake as stalled (`valid && !ready`), starved (`!valid && ready`),
transferred (`valid && ready`) or idle, plus the `m0_en` / `m1_en` / `m2_en`
port occupancy and the arbitration-request stalls
(`hf_m1_req && !hf_m1_gnt`, `hf_m2_req && !hf_m2_gnt`, `qa_pend && !qa_gnt`).
All figures below are **simulated**, never measured (spec §9, CLAUDE.md).

Provenance: bench, RTL and `sram_macro_model.v` at commit `61644ee` (branch
`feature/issue-119`; `rtl/` identical to main `d7bf183`). Every generated
image was sha256-checked against `verification/images/SHA256SUMS` before
encoding (`load_image`, shared with `test_top_golden.py`); the pixel stream
was exactly 921,600 bytes (1200 MCUs x 768) and `status_error` was 0 at the
end of each frame.

## Non-intrusiveness first

Same seed (1), same images, same driver: the three rows' pinned figures are
**identical** to the committed `20261114T0551Z-frame-cycles-62d88e1/cycles.json`
— 982,471 / 1,103,167 / 1,740,070 cycles to `out_last`, 18,616 / 126,543 /
360,997 output bytes, `golden_match` true on all three. The sampler reads
wires; it drives nothing.

One measurement-definition note, recorded rather than smoothed over:
`cycles_to_out_last` is `int((last_ns - start_ns) / 10)` over float
nanoseconds. Rows 2 and 3 carry ~1 ps of accumulated simulator clock drift
(the cocotb `Clock` driver's timer rounding over ~2 ms of sim time; visible
as `.001` / `.002` ns offsets in `stage_sample_window_ns`), which makes that
float quotient land epsilon above an integer, and `int()` floors it one
cycle low. The true integer edge counts between the frame-start edge and the
`out_last` edge are **1,103,168** and **1,740,071** (`stage_sample_cycles` in
`cycles.json`, and the sampler window is asserted against exactly this
integer count). The 1-cycle delta (0.00006%) changes no conclusion in this
or the earlier record: the q95 row still exceeds the frame period. Row 1 is
drift-free and exact in both. The committed §9 figures keep the original
formula unchanged; both numbers are recorded per row.

## Result: the binding stage

Walking each row from the output inward — a boundary's stall only matters if
its consumer is not itself blocked — the first boundary with a large stalled
count is the binding one. `s7` (jc_huff → jc_bitpack) stalls 9 cycles at q95
and 0 elsewhere; `bp` and `out` stall 0 on every row, so `jc_bitpack` and
`jc_out_mux` are exonerated. Everything upstream is backed up behind
**`jc_huff`**: `s6` (jc_quant → jc_huff, `s6_valid && !s6_ready`) stalls
1,268,261 cycles at q95 — 72.9% of the frame window, 1056.9 cycles/MCU.

Stalled cycles per boundary (`valid && !ready`), per row:

| Boundary (producer → consumer) | `scene_fbm` q50 | `noise_max_entropy` q50 | `noise_max_entropy` q95 |
|---|---|---|---|
| `pix` (host → jc_downsample) | 59,995 | 180,233 | 815,795 |
| `s2` (jc_downsample → jc_mb_ctrl) | 51,589 | 170,534 | 801,864 |
| `s3` (jc_mb_ctrl → jc_dct) | 636,019 | 895,642 | 1,545,304 |
| `s4` (jc_dct → jc_zigzag) | 0 | 180,585 | 817,231 |
| `s5` (jc_zigzag → jc_quant) | 108,350 | 637,856 | 1,278,299 |
| `s6` (jc_quant → jc_huff) | 79,550 | 610,671 | **1,268,261** |
| `s7` (jc_huff → jc_bitpack) | 0 | 0 | 9 |
| `bp` (jc_bitpack → jc_out_mux) | 0 | 0 | 0 |
| `out` (jc_out_mux → host) | 0 | 0 | 0 |

The upstream stalls (pix, s2, s3, s4, s5) are downstream cascade: with
`jc_huff` not accepting, `jc_quant` fills, then `jc_zigzag`, then the DCT,
then the macroblock controller, and the input FIFO fills behind it. At
`scene_fbm` q50 the picture is the one record 0005 §7 predicts for typical
content: `s6` stalls only 66.3 cycles/MCU and the largest direct
consumer-side stall is `s3` (jc_dct not accepting, 636,019 cycles) — the DCT
binds, loosely.

## The q95 row confirms the predicted jc_huff floor

The issue's curation predicted, from the golden model and a reading of
`jc_huff`'s four-state blocking FSM (every symbol costs at least the
`ST_IN` → `ST_ISSUE` → `ST_WAIT` → `ST_OUT` round trip, ≥4 cycles; a zero AC
coefficient inside a run costs one cycle in `ST_IN`): a throughput floor of
4 × symbols + in-run zeros = **1448.2 cycles/MCU**, i.e. 1,737,840 cycles
over 1200 MCUs.

Counted in simulation: the true frame count is **1,740,071** cycles — the predicted floor
plus 2,231 cycles (0.13%), which is the 627-byte header, first-MCU fill and
final drain. **Confirmed.** The prediction is a golden-model tally; this
count is RTL simulation; both now exist and agree. (The `s7` transferred
count independently cross-checks: 425,695 symbol beats at q95 against the
golden-model tally of 425,700 symbols — five apart, an EOB-edge counting
difference in the software tally, not in the RTL.)

Per row, predicted floor (`4 × symbols + zeros`, × 1200 MCUs) against the
true simulated frame count:

| Row | Predicted jc_huff floor | True simulated cycles | Delta |
|---|---|---|---|
| `scene_fbm` q50 | 560,640 (467.2/MCU) | 982,471 | huff does **not** bind (DCT does) |
| `noise_max_entropy` q50 | 1,091,892 (909.9/MCU) | 1,103,168 | +10,288 (+0.94%) |
| `noise_max_entropy` q95 | 1,737,840 (1448.2/MCU) | 1,740,071 | +2,231 (+0.13%) |

## Which row of record 0005 §7 this contradicts

Row 4, "Huffman symbol path", budget **952 cycles/MCU**. The counted q95
frame is 1450.06 cycles/MCU (1,740,070/1200; the true count gives 1450.06
rounded the same) — **1.52× the budgeted row**. The row's derivation
("Y block: 80 M1 accesses x A = 160 + 10 fill; Cb/Cr block: 63 M2 accesses x
2 = 126 + 10; 4 x 170 + 2 x 136") prices ~2.1 cycles per symbol, about half
what the four-state FSM actually costs. The access count is not the problem:
the §7 M1 port row ("354 accesses x 2 = 708") budgets 708 cycles/MCU of M1
occupancy, and the counted `m1_en` occupancy at q95 is 411,326 cycles/frame
= 342.8/MCU — the row is loose, not broken. Arbitration is exonerated too:
`hf_m1_req && !hf_m1_gnt` stalls 9 cycles at q95 (221 / 3,050 on the other
rows) and the quantizer holder's `qa_pend && !qa_gnt` 4,826 — jc_huff and
the quantizer share M1 through `u_arb1` and contention is negligible. What
is broken is the per-symbol cycle price: the FSM floor, not memory access,
is the binding cost.

## DUT-side stall observations (from absorbed #121)

The two self-readback counters (`out_ready_stall_cycles`,
`pix_valid_gap_cycles` — each read back a signal the bench itself drove one
statement earlier and so could never fail) are **gone**. In their place,
DUT-side observations the bench does not control: `pix_valid && !pix_ready`
(`pix_valid_not_ready_cycles` — input backpressure the DUT imposed: 59,995 /
180,233 / 815,795 cycles; the DUT's input path genuinely backpressures a
host that never stalls, and the frame total is set downstream of it) and
`out_valid && !out_ready` (`out_valid_not_ready_cycles` — 0 on every row,
0 by construction while the bench holds `out_ready` high; the structural
no-stall drive is unchanged and the 0 is asserted). Full per-boundary,
occupancy and arbitration figures are machine-written in `cycles.json`
(schema_version 2, with the boundary→producer→consumer legend inline).

Per-boundary accounting closes: for every boundary and row,
stalled + starved + transferred + idle = `stage_sample_cycles`, and
`stage_sample_cycles` = the integer cycle count
`(beat_ps - start_ps) // 10_000`. `pix.transferred` = 921,600 (the pixel
stream) and `out.transferred` = `output_bytes` on every row, cross-checking
the sampler against the byte-collecting monitors.

## Tools, host and wall time

- Icarus Verilog **13.0** (stable), cocotb **2.1.0**, Pillow **10.2.0**,
  CPython **3.12.3**, seed 1 — same versions as
  `20261114T0551Z-frame-cycles-62d88e1`.
- klt **0.8.0** (`klayout-tools[functional-verification]==0.8.0`) for
  `report.json`, in a throwaway `uvx` environment — the host toolchain was
  not modified.
- Wall time (cocotb per-test real time, shared 8-vCPU worker): the bench run
  and the independent klt run each re-ran all three rows; per-row
  `wall_time_s` is in `cycles.json`, `real_time_s` in `report.json`. The
  sampler's per-edge VPI reads make the bench run ~35% slower than the
  earlier record (~11.2 min vs ~8.3 min total); cycle counts are
  unaffected, as the identity check above shows. The klt run's log carries
  the same three cycle/byte figures line for line.
- Not split: one cocotb process, three tests, sequential. RTL digital
  simulation; no batch fleet involved.
- **Not added to any CI or required job.**

## Verdict and where the decision went

The binding stage at q95 is `jc_huff`, the contradicted budget row is
record 0005 §7 row 4, and decision record
`spec/decision-records/0008-huff-cycle-budget.md` (filed from this record)
chooses option (a) — correct record 0005 §7's budget rows to bound the real
design — over (b) an immediate RTL change and (c) a §9 quality-range note.
Implementing the correction, and the q95 gap closure it leaves open, are
follow-up work filed from that record; nothing in this record edits record
0005, the spec, or the RTL.

## Reproducing (cold start)

```sh
bash .github/scripts/install-oss-cad-suite.sh      # -> ~/oss-cad-suite
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install 'cocotb==2.1.0' 'pillow==10.2.0'

# from the repository root; exit 1 = a row failed (today: the q95 range
# assertion, the #119 finding), 2 = the suite did not run
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
    < verification/records/20261115T0046Z-frame-stages-61644ee/request.json \
    > report.json
# klt: 0 every test passed, 3 a test failed (today: 3), 1 request/environment error
```

Both routes are deterministic at seed 1. `cycles.json` is written by the
bench itself; `report.json` is committed exactly as klt emitted it.

## Append-only

This record is evidence, not a working document: do not edit or delete it.
A later run goes in a new directory.
