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
| [decision-records/0009-klt-pin-and-attest-binding.md](decision-records/0009-klt-pin-and-attest-binding.md) | klt pin and the item-1 attestation binding | proposed |
| [decision-records/0010-retime-depth-allowance.md](decision-records/0010-retime-depth-allowance.md) | Retime depth allowance: measurement-bounded depth for `colour_convert` and `jc_quant_core`, retime span, band pricing; §5's q95 column classified | Decided, 2026-11-15 (issue #144) |
| [decision-records/0011-quant-pipeline-depth.md](decision-records/0011-quant-pipeline-depth.md) | The `jc_quant_core` pipeline depth, measured: five stages under 0010 §1's allowance, row 3 and the §5 increment priced at the measured depth; the mapper carry-select-collapse finding | Decided, 2026-11-15 (issue #133) |

Recorded statuses are transcribed from each record's status line as
committed; changing a record's status is its own decision record, not an edit
here. Two records carry the number `0001` and two carry `0005` — the
filenames disambiguate them. A change to a ratified row needs a new decision
record, not an edit.
