# spec

Ratified specification and decision records. See the repo README for scope.

| Document | Content |
|---|---|
| [codec.md](codec.md) | The ratified target spec: modes, arithmetic, framing, throughput, corners, memory, golden model, reference images |
| [decision-records/0002-input-order-and-buffering.md](decision-records/0002-input-order-and-buffering.md) | Block-ordered input, one double-buffered macroblock |
| [decision-records/0003-dct-arithmetic.md](decision-records/0003-dct-arithmetic.md) | DCT arithmetic, bit for bit |
| [decision-records/0004-sram-source.md](decision-records/0004-sram-source.md) | SRAM source: adopt `gf180-sram` |
| [decision-records/0005-rtl-microarchitecture.md](decision-records/0005-rtl-microarchitecture.md) | RTL microarchitecture: module split, pin-level interface, memory access, cycle budget |

Record `0001` (the PDK pin) is owned by issue #5 and is not yet committed.
A change to a ratified row needs a new decision record, not an edit.
