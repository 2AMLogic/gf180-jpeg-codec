# Decision record 0013: the frame bound after record 0009's `jc_huff` pipelining — per-depth slowest-stage rows (60.8% at depth 8 to 88.4% at depth 12), not the pre-0009 90.2%

**Status**: Decided, 2026-11-17 (issue #196)
**Resolves**: #196 — `0007-pre-route-setup-shortfall.md` (§4 and §5), `0010-retime-depth-allowance.md` (Evidence and §4), `0011-stage1-retime-latency-pricing.md` (header, Evidence and Decision) and `0012-quant-pipeline-depth.md` (§2) still cite **90.2% at every depth in the band** — the bound obtained by pricing the pre-0009 §7 row 5 (1249 cycles/MCU) as the binder. The merged `0005-rtl-microarchitecture.md` §7 (as rewritten by `0009-huff-symbol-path-pipelining.md`) derives the operative bound from the slowest stage: **60.8% (depth 8) to 88.4% (depth 12)** at worst-case content.
**Spec**: `spec/codec.md` §9, §10 unchanged; this record only restates the frame bound as already derived in `spec/decision-records/0005-rtl-microarchitecture.md` §7 and amends the four records above by pointer. No ratified bound changes and no new model: every figure below is §7's own or is recomputed from §7's rows by its stated model.

Filed as 0013 — the next free number at build time; the directory already carries duplicate `0001`, `0005` and `0009` numbers, so records are cited by filename, not number alone.

## Question

Records 0007, 0010, 0011 and 0012 — decided before or alongside PR #152's `0009-huff-symbol-path-pipelining.md` — publish the target-mode frame bound as **90.2% at every depth in the band** (1,503,866 / 1,503,890 / 1,504,070 cycles against the 1,666,667-cycle period). That figure prices §7 row 5 (bit pack at worst-case content, 1249 cycles/MCU) as the binder and carries the pre-0009 row 4 (952) in the first-MCU latency term. PR #152 rewrote `0005-rtl-microarchitecture.md` §7 around record 0009's pipelined `jc_huff`: row 4 dropped to a counted-derived 745.2 cycles/MCU and the binder at worst-case content moved to stage 2. Which frame bound is operative on the merged tree, and what do the four records' 90.2% statements now mean?

## Evidence

The model is `0005-rtl-microarchitecture.md` §7's own, unchanged: throughput of the pipeline is set by its slowest stage, not by the sum of the stages; the serial sum of the five stage rows is reported only as the bound on first-MCU latency. The target-mode frame bound is

> 1200 × (slowest-stage cycles per MCU) + (first-MCU latency sum) + 627 header cycles

against the period 50e6 / 30 = **1,666,667** cycles.

**Which stage binds.** Under `0009-huff-symbol-path-pipelining.md` row 4 counts a derived 745.2 cycles/MCU at q95 ((2 × 425,695 + 39,211 + 3,624) / 1200) — below the 768-cycle input row, so stage 4 never binds at any content or quality (§7). Row 5's 1249 remains §3's theoretical per-block bound at hypothetical all-max-symbol content; on the named §12 images the scan output counts 300.8 bytes/MCU at q95 and stage 5 does not bind (§7). The binder at worst-case content is therefore **stage 2, the DCT**: (16d + 12) × 6 = 96d + 72 cycles/MCU at d cycles/vector, over 0007 §4's authorized band d = 8 … 12.

**Per-depth rows.** The stage-3 term is §7's own table row (432) in the depth-8 row and 0007 §4's re-derived row at the decided quant latency (438, k = 1) in the depth-10 and depth-12 rows — the 6-cycle difference moves no percentage at two decimals. Rows 8, 10 and 12 are §7's published figures; rows 9 and 11 are recomputed here from the same §7 rows and model:

| d (cycles/vector) | Stage 2 = 96d + 72 | First-MCU latency | Frame bound = 1200 × stage 2 + latency + 627 | % of 1,666,667 | Period buys (derived) |
|---|---|---|---|---|---|
| 8 | 840 | 4,034 | **1,012,661** | **60.8%** | 49.4 frames/s |
| 9 | 936 | 4,136 | **1,127,963** | **67.7%** | 44.3 frames/s |
| 10 (decided, `0010-retime-depth-allowance.md`) | 1032 | 4,232 | **1,243,259** | **74.6%** | 40.2 frames/s |
| 11 | 1128 | 4,328 | **1,358,555** | **81.5%** | 36.8 frames/s |
| 12 (band edge) | 1224 | 4,424 | **1,473,851** | **88.4%** | 33.9 frames/s |

Every latency term is the serial sum of §7's five stage rows (768 + stage 2 + stage 3 + 745.2 + 1249, floored at the decimal). The depth-10 row sits 207 cycles under 0007 §4's published 1,243,466 and the depth-12 row 15 under the corresponding 1,473,866 (which reuses 0007 §4's depth-10 latency term, as `0009-huff-symbol-path-pipelining.md` re-derives) — the differences are exactly the row-4 repricing 952 → 745.2. The "period buys" column is the rate the bound implies against the signoff clock; it is derived, not measured.

**Quant-latency sensitivity.** `0012-quant-pipeline-depth.md` later measured the quant depth at five stages (stage 3 = 462). Recomputing the latency sums with 462 moves the depth-10 bound to 1,243,283 and the depth-12 bound to 1,473,875 — +24 cycles each; every percentage is unchanged at two decimals (74.6%, 88.4%).

**Counted cross-checks** (counted in simulation, never measured): on the depth-8 tree, record 0009's `verification/records/20261115T1237Z-frame-stages-pipelined-83423424/` counted 1,088,887 cycles to `out_last` (65.3% of the period, 45.9 frames/s simulated); on the merged tree, the committed re-count `verification/records/20261117T2156Z-frame-cycles-depth12-39c70b2/` (issue #197) counted 1,383,369 ±1 (83.0%, 36.1 frames/s simulated, `golden_match` true, byte counts unchanged; the pre-#208 bench that produced the record resolved `cycles_to_out_last` to ±1, position-dependent within a simulation — the record's "Disposition of the quoted 1,383,370" § carries the resolution; since #208/#209 the bench derives the count from integer-ps endpoints and resolves it exactly) — both consistent with the rows above and inside §9.

**What the 90.2% figures were.** Each pre-0009 statement prices 1200 × 1249 (row 5 as binder) plus a latency sum containing row 4 at 952 — 4439 (0007 §4 and 0011's header), 4643 (0010 Evidence's band edge, "first-MCU latency 4439 … 4643 over the band"), 4463 (0012 §2 at 0012's measured quant depth) — giving 1,503,866 / 1,504,070 / 1,503,890 in the same order, all 90.2%. Under record 0009 that pricing has no operative content on the merged tree: row 4 no longer costs 952 and row 5 does not bind on any named image. The figure survives only as a description of the pre-0009 tree.

## Decision

1. **The operative frame bound at the target is the merged §7 slowest-stage row**: 60.8% of the period at depth 8, 74.6% at the decided depth 10, 88.4% at the band-edge depth 12, at worst-case content — all inside §9's 30-frames/s budget, with the counted rows above as the simulation evidence. No ratified bound changes: §9's per-stage limits and §2's targets are untouched, and no cycle figure outside the superseded 90.2% rows moves.

2. **The four records' 90.2% statements are scoped to the pre-0009 tree by amendment pointer**, not edited. Each pointer names this record and states that the site's figure prices the pre-0009 §7 row 5 as the binder with row 4 at 952, superseded by the merged §7 rows above. Sites (line numbers on the tree carrying this record — `main` once it lands; they do not resolve on the pre-0013 tree, where this PR's own pointer paragraphs have not yet shifted them — re-verified with `sed -n '<n>p'` at build time):
   - `0007-pre-route-setup-shortfall.md:217` — §4's "1,503,866 (90.2%)" worst-case bound; `:247` — §5's "90.2% at every depth in the band".
   - `0010-retime-depth-allowance.md:132` — Evidence's "1,503,866 – 1,504,070 cycles = 90.2% at every depth in the band"; `:233` — §4's "90.2% at every depth in the band (row 5's 1249 dominates throughout)".
   - `0011-stage1-retime-latency-pricing.md:5` — the header's "the 4439 first-MCU latency sum, and the 90.2% frame bound all stand as ratified"; `:47` — "inside the 90.2% figure's rounding"; `:77` — "the 90.2% frame figure all stand".
   - `0012-quant-pipeline-depth.md:120` — §2's "1,503,890 (90.2%, was 90.2%)".

3. **What stands in each record despite the scoping**: 0007's clock-target response and §4's band pricing; 0010's measured-depth allowance and its §4 classification of the additive q95 column as a sensitivity; 0011's subject — stage-1 latency priced at `L`, not `6L` — whose conservative-direction finding remains true against the corrected bound (the ≤ 235-cycle over-statement is still < 0.02% of 1,243,259); 0012's measured quant depth and its re-priced §5 increment (+222), whose "no conclusion moves" verdict survives — its 74.6% typical-content row already matched the corrected model at two decimals.

## Consequences

- `git grep -n "90.2" -- spec` on the tree carrying this record hits only: the four records' original sentences (eight sites), one amendment pointer paragraph per record — each names the sites it scopes (0007's, for example, covers "§4's 1,503,866 above and §5's 'at every depth in the band' below"), so a site usually sits above its pointer rather than immediately following one — this record's own quotations of those sentences, and the new `spec/README.md` index row quoting the figure. `0005-rtl-microarchitecture.md` §7 and `0009-huff-symbol-path-pipelining.md` carry no 90.2% figure.
- Any successor record citing the target-mode frame bound cites these rows (60.8% / 67.7% / 74.6% / 81.5% / 88.4% at depths 8 / 9 / 10 / 11 / 12) or `0005-rtl-microarchitecture.md` §7 directly — never the 90.2% figure, which is now historical.
- The 1,503,866 / 1,503,890 / 1,504,070-cycle figures remain in the four records as committed history; this record does not edit them.
