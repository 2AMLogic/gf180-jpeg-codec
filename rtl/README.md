# rtl

Module names, ports and stream widths are fixed by
`spec/decision-records/0005-rtl-microarchitecture.md`; one module per file.

| File | Module | Issue |
|---|---|---|
| `jc_zigzag.v` | ping-pong coefficient buffers C0/C1 and zig-zag read-out (S4 to S5) | #45 |
| `jc_huff.v` | DC prediction, run-length/ZRL/EOB, Huffman lookup on M1/M2, additional bits (S6 to S7) | #45 |
| `jc_bitpack.v` | MSB-first packer, `FF 00` stuffing, 1-bit padding (S7 to S8) | #45 |
| `smoke_placeholder.v` | verification-skeleton stand-in, not the codec | #6 |
