# rtl

Module names, ports and stream widths are fixed by
`spec/decision-records/0005-rtl-microarchitecture.md`; one module per file.

| File | Module | Issue |
|---|---|---|
| `jc_zigzag.v` | ping-pong coefficient buffers C0/C1 and zig-zag read-out (S4 to S5) | #45 |
| `jc_huff.v` | DC prediction, run-length/ZRL/EOB, Huffman lookup on M1/M2, additional bits (S6 to S7) | #45 |
| `jc_bitpack.v` | MSB-first packer, `FF 00` stuffing, 1-bit padding (S7 to S8) | #45 |
| `jc_cfg_regs.v` | configuration port decode, MODE/WIDTH/HEIGHT, status, sticky error cause, frame start / `frame_active` | #46 |
| `jc_table_load.v` | table-byte intake (read-modify-write), validation, canonical code generation, Annex K reset load | #46 |
| `jc_table_load_rom.v` | generated Annex K payload ROM for the reset load (`verification/rtl/gen_table_rom.py`) | #46 |
| `jc_header_gen.v` | JFIF/JPEG header and `EOI`, QOI header and end marker, from the raw payload bytes in M1/M2 | #46 |
| `jc_out_mux.v` | header / scan / trailer ordering onto the byte output, `out_last` | #46 |
| `jc_qoi.v` | QOI chunk encoder (spec §8), 64-word index in M0 words 192 to 255 | #47 |
| `smoke_placeholder.v` | verification-skeleton stand-in, not the codec | #6 |
