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
| `jpeg_codec_top.v` | top level: port list of record 0005 section 3, all stages, three memory instances, mode fan-out | #48 |
| `jc_sram_wrap.v` | one `gf180-sram` 256 x 32 macro behind `{en, we, addr, wdata, rdata}`; the macro is a black box in synthesis (`flow/sram_blackbox.v`) | #48 |
| `jc_sram_arb.v` | fixed-priority N-requester arbiter in front of one wrap, enforces access time A = 2 | #48 |
| `jc_downsample.v` | pixel ingest, `colour_convert`, 2 x 2 chroma average, word packing into S2 writes | #48 (see note) |
| `jc_mb_ctrl.v` | macroblock buffers A/B, M0 write-before-read arbitration, S3 read sequencing | #48 (see note) |
| `smoke_placeholder.v` | verification-skeleton stand-in, not the codec | #6 |

Note: record 0005 section 2 assigns `jc_downsample` and `jc_mb_ctrl` to #42, but
#42 delivered only the combinational `colour_convert` and `chroma_downsample`,
so the sequential ingest stage that connects them to M0 was written with the
integration in #48. `colour_convert` is used under its #42 name rather than
`jc_color_convert`.
