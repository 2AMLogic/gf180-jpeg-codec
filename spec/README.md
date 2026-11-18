# spec

Ratified specification and decision records. See the repo README for scope.

| Document | Content | Recorded status |
|---|---|---|
| [codec.md](codec.md) | The ratified target spec: modes, arithmetic, framing, throughput, corners, memory, golden model, reference images | ratified 2026-10-17 (issue #3) |
| [decision-records/0001-harness-divergence.md](decision-records/0001-harness-divergence.md) | Harness divergence from gf180-polysynth | accepted |
| [decision-records/0001-pdk-pin.md](decision-records/0001-pdk-pin.md) | PDK pin | proposed |
| [decision-records/0002-input-order-and-buffering.md](decision-records/0002-input-order-and-buffering.md) | Block-ordered input, one double-buffered macroblock | Decided, 2026-10-17 |
| [decision-records/0003-dct-arithmetic.md](decision-records/0003-dct-arithmetic.md) | DCT arithmetic, bit for bit | Decided, 2026-10-17 |
| [decision-records/0004-sram-source.md](decision-records/0004-sram-source.md) | SRAM source: adopt `gf180-sram` | Decided, 2026-10-17 |
| [decision-records/0005-item6-row-accounting.md](decision-records/0005-item6-row-accounting.md) | §11 accounts for every §1 row (T1 item 6) | Decided, 2026-10-27 |
| [decision-records/0005-rtl-microarchitecture.md](decision-records/0005-rtl-microarchitecture.md) | RTL microarchitecture: module split, pin-level interface, memory access, cycle budget | Decided, 2026-10-27 |
| [decision-records/0006-odd-size-padding.md](decision-records/0006-odd-size-padding.md) | Odd-size padding versus libjpeg-turbo | Decided, option A (operator ruling, 2026-10-30) |
| [decision-records/0007-pre-route-setup-shortfall.md](decision-records/0007-pre-route-setup-shortfall.md) | Pre-route setup shortfall response: pipelining direction, per-module depth targets, cycle cost | Decided, 2026-11-14 |
| [decision-records/0008-huff-cycle-budget.md](decision-records/0008-huff-cycle-budget.md) | Huffman cycle budget: the counted `jc_huff` binding stage; §7 row 4 does not bound the design | Decided, option A (2026-11-15, issue #119) |
| [decision-records/0009-huff-symbol-path-pipelining.md](decision-records/0009-huff-symbol-path-pipelining.md) | Pipelining the `jc_huff` symbol path: the q95 frame-rate remedy, §7 row 4 re-derived | Decided, 2026-11-15, issue #137 |
| [decision-records/0009-klt-pin-and-attest-binding.md](decision-records/0009-klt-pin-and-attest-binding.md) | klt pin and the item-1 attestation binding | proposed |
| [decision-records/0010-retime-depth-allowance.md](decision-records/0010-retime-depth-allowance.md) | Retime depth allowance: measurement-bounded depth for `colour_convert` and `jc_quant_core`, retime span, band pricing; §5's q95 column classified | Decided, 2026-11-15 (issue #144) |
| [decision-records/0011-stage1-retime-latency-pricing.md](decision-records/0011-stage1-retime-latency-pricing.md) | Stage 1's retime latency pricing: `L` beats of inserted chroma-lane latency cost `L` cycles of first-MCU latency, not `6L`; 0010 §3's price corrected, no bound changes | Decided, 2026-11-16 (issue #160) |
| [decision-records/0012-quant-pipeline-depth.md](decision-records/0012-quant-pipeline-depth.md) | The `jc_quant_core` pipeline depth, measured: five stages under 0010 §1's allowance, row 3 and the §5 increment priced at the measured depth; the mapper carry-select-collapse finding | Decided, 2026-11-15 (issue #133) |
| [decision-records/0013-post-0009-frame-bound.md](decision-records/0013-post-0009-frame-bound.md) | The frame bound after `jc_huff` pipelining: the merged 0005 §7 slowest-stage rows (60.8% at depth 8 to 88.4% at depth 12 at worst-case content) replace the pre-0009 90.2%-at-every-depth figure; 0007/0010/0011/0012's citations scoped by pointer | Decided, 2026-11-17 (issue #196) |
| [decision-records/0014-jc-dct1d-datapath-restructure.md](decision-records/0014-jc-dct1d-datapath-restructure.md) | The `jc_dct1d` datapath restructure, measured: CSD carry-save constant multiply and sliced combine at 13 cycles/vector, ≥ 0 ns setup slack at all five §10 views (`fmax` 50.79 MHz at the signoff view), §2's ≥ +6.7 ns half reported unmet; 0007 §1's pipelining-only clause given up for this module and §4's ≤ 12 band superseded, per the operator's option-a ruling | Proposed, 2026-11-18 (issue #169) |

Recorded statuses are transcribed from each record's status line as
committed; changing a record's status is its own decision record, not an edit
here. Two records carry the number `0001`, two carry `0005`, and two carry
`0009` — the
filenames disambiguate them. A change to a ratified row needs a new decision
record, not an edit.
