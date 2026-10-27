# Decision record 0005: RTL microarchitecture, stage split, pin-level interface, cycle budget

**Status**: Decided, 2026-10-27
**Resolves**: the "pin-level host interface, micro-architecture, pipeline stage split" row of `spec/codec.md` §14 (#4 item 1, #41)
**Spec**: `spec/codec.md` §3 (host interface), §9 (throughput), §13 (memory); records 0002 to 0004

## Question

`spec/codec.md` §3 specifies the host interface by behaviour only, and §14
defers the pin list, the module split and the stage budgets to the RTL
architecture. The seven stage issues (#42 to #47) and the integration issue
(#48) are built in parallel, so they need fixed module names, stream widths,
memory-access rules and cycle budgets before any RTL is written.

Evidence tiers are those of the spec: **derived** = arithmetic from stated
formulas, reproducible from this page. Nothing here is measured; no RTL
exists yet, so every cycle figure is a **budget the stage must meet**, not a
result. A budget is checked by the stage's own testbench and, for frame rate,
by cycles counted in simulation on a named image (spec §9).

## Assumption: macro access time A

The `gf180-sram` macro has no Liberty view yet (record 0004), so its access
time is unknown. This record budgets every SRAM access at **A = 2 cycles**:
the request is presented in cycle t, read data is valid in cycle t+1, and the
next access to the same instance starts in cycle t+2 (no overlap). A = 2 is
the bound record 0004 derives for the table path (`L <= 2`) and is inside the
spec §9 limit of 7 for the macroblock buffer. If the Liberty views show a
larger A, the budgets below that use it (M0, M1, M2 rows) are re-derived in a
new record, not edited here.

## Decision

### 1. Clocking and conventions

One clock `clk`, one synchronous active-low reset `rst_n`, rising-edge
registers, Verilog-2001 (Icarus/Yosys), no latches. Every stream is
valid/ready: a beat transfers in a cycle where both are high; `valid` once
raised is held with stable payload until `ready`. Names: the top module is
`jpeg_codec_top`; every other module is prefixed `jc_`; **one module per
file**, file name = module name + `.v`, all under `rtl/` (flat).

### 2. Module hierarchy and ownership

| Module (file `rtl/<name>.v`) | Function | Owner |
|---|---|---|
| `jpeg_codec_top` | top level: port list of section 3, instantiation of everything below, mode fan-out of the pixel and byte streams | #48 |
| `jc_sram_wrap` | adapts one `gf180-sram` macro (pins `A, CEN, CLK, D, Q, GWEN, WEN`, record 0004) to `{en, we, addr[7:0], wdata[31:0], rdata[31:0]}`; whole-word writes only, so no byte-enable width is assumed | #48 |
| `jc_sram_arb` | N-requester fixed-priority arbiter in front of one wrap; used for M1 (4 clients) and M2 (3 clients); M0 has two mode-exclusive clients and is muxed by mode in `jpeg_codec_top` | #48 |
| `jc_color_convert` | RGB to YCbCr (spec §4), 3 beats in per pixel; grey passes the byte as Y | #42 |
| `jc_downsample` | 2 x 2 chroma average with the §4 bias, in-macroblock pixel position, packing of 4 samples per word, word-write requests | #42 |
| `jc_mb_ctrl` | macroblock buffer A/B bookkeeping, M0 arbitration (write before read), read-side sequencing of block words to the DCT | #42 |
| `jc_dct` (+ `jc_dct1d`, `jc_xpose_rf`) | level shift, two passes of record 0003, the 64 x 14 transpose register file | #43 |
| `jc_zigzag` | ping-pong coefficient buffers C0/C1 (64 x 15 bit register files) and the zig-zag read-out | #45 |
| `jc_quant` | rounding quantizer of spec §5, Q read sequentially from M1 | #44 |
| `jc_huff` | DC prediction, run-length/ZRL/EOB, Huffman lookups on M1/M2, additional bits | #45 |
| `jc_bitpack` | MSB-first accumulator, `FF 00` stuffing, final 1-bit padding, byte stream | #45 |
| `jc_cfg_regs` | configuration port decode, mode/size registers, status, error cause, frame start | #46 |
| `jc_table_load` | table-byte intake, validation, canonical code generation, Annex K reset defaults, M1/M2 table writes | #46 |
| `jc_header_gen` | JFIF/JPEG header and `EOI`, QOI header and end marker, from the raw payload bytes in M1/M2 | #46 |
| `jc_out_mux` | orders header, scan and trailer onto the single byte output; drives `out_last` | #46 |
| `jc_qoi` | QOI encoder (spec §8), 64-word index in M0 words 192 to 255 | #47 |

A module that a stage issue finds it must split further may add files with
its own `jc_<stage>_` prefix; it may not rename or re-port a module in this
table without a new record.

### 3. Top-level port list

Direction is from the chip. Widths in bits.

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | in | 1 | clock |
| `rst_n` | in | 1 | synchronous reset, active low; starts the Annex K default table load (busy until done) |
| `pix_data` | in | 8 | pixel byte |
| `pix_valid` | in | 1 | |
| `pix_ready` | out | 1 | low while the next macroblock buffer is busy, when no frame is started, and after the frame's last pixel |
| `out_data` | out | 8 | file byte |
| `out_valid` | out | 1 | |
| `out_ready` | in | 1 | |
| `out_last` | out | 1 | with the final byte of the file (`EOI` second byte, or the last QOI end-marker byte) |
| `cfg_valid` | in | 1 | configuration or table byte write |
| `cfg_ready` | out | 1 | low only while a read-modify-write of a table word is in progress |
| `cfg_addr` | in | 10 | byte address, map below |
| `cfg_wdata` | in | 8 | byte |
| `status_idle` | out | 1 | no frame, commit or reset load in progress |
| `status_busy` | out | 1 | complement of `status_idle` |
| `status_error` | out | 1 | sticky until cleared |
| `err_cause` | out | 4 | cause code of the first error since the last clear, 0 if none |

Mapping of the §3 interface table, row by row:

| §3 row | Named ports |
|---|---|
| Pixel input: 8-bit data, valid/ready, 3 beats per pixel (colour, QOI), 1 per pixel (grey) | `pix_data[7:0]`, `pix_valid`, `pix_ready`; beat order R, G, B; the beat count per pixel follows `MODE` |
| Byte output: 8-bit data, valid/ready, `last` on the final byte | `out_data[7:0]`, `out_valid`, `out_ready`, `out_last` |
| Configuration and table load: mode, width, height, table payloads in segment byte format, idle only, a violating write sets an error flag and changes nothing | `cfg_valid`, `cfg_ready`, `cfg_addr[9:0]`, `cfg_wdata[7:0]`; map below; a write while `status_busy` is accepted (`cfg_ready` high), discarded, and raises `LOAD_WHILE_BUSY` |
| Status: idle / busy / error, cause readable | `status_idle`, `status_busy`, `status_error`, `err_cause[3:0]` |
| Back-pressure paragraph | output stalls through `out_ready`; input stalls through `pix_ready`; no frame buffer exists, nothing is dropped |

**Configuration address map** (byte writes; table windows are the DQT and DHT
payload bytes of spec §5, §6 in segment order, without marker or length):

| Address | Register or window | Notes |
|---|---|---|
| `0x000` | `MODE` | 0 colour JPEG, 1 grey JPEG, 2 QOI; 3 reserved (`BAD_CONFIG` at start) |
| `0x001`, `0x002` | `WIDTH` low, high | 1 to 65535 |
| `0x003`, `0x004` | `HEIGHT` low, high | 1 to 65535 |
| `0x005` | `CMD` | 1 = start frame, 2 = commit tables, 4 = clear error; other values `BAD_CONFIG` |
| `0x040` to `0x07F` | DQT 0 (luma), 64 B zig-zag | |
| `0x080` to `0x0BF` | DQT 1 (chroma), 64 B zig-zag | |
| `0x100` to `0x11B` | DHT DC 0, `BITS[1..16]` then `HUFFVAL`, up to 28 B | |
| `0x140` to `0x1F1` | DHT AC 0, up to 178 B | |
| `0x200` to `0x21B` | DHT DC 1 | |
| `0x240` to `0x2F1` | DHT AC 1 | |

Any other address raises `ADDR_UNMAPPED`. **Error causes**: 0 none, 1
`LOAD_WHILE_BUSY`, 2 `ZERO_QUANT`, 3 `BAD_HUFFMAN`, 4 `BAD_CONFIG` (width or
height 0, reserved mode or command), 5 `ADDR_UNMAPPED`, 6 `TABLE_INVALID`
(start requested with a table that failed or is uncommitted). The first
cause since the last clear is kept; `CMD = 4` clears it only while idle.
There is no abort command: a started frame ends only by completing or by
`rst_n`.

**Frame sequence.** Host writes `MODE`, `WIDTH`, `HEIGHT` and, if it wants
non-default tables, the table windows; writes `CMD = 2` (commit; busy while
the loader validates and builds the lookups); writes `CMD = 1`. The chip
latches mode and size, emits the header, accepts pixels and emits the scan
and trailer; `out_last` ends the frame and `status_idle` rises with the
last transfer. The chip derives the pixel count itself: colour
`16 * 16 * ceil(W/16) * ceil(H/16)` pixels, grey `64 * ceil(W/8) * ceil(H/8)`,
QOI exactly `W * H` (host padding, spec §2).

**Table acceptance.** Raw payload bytes are written straight to their M1/M2
regions (read-modify-write, hence `cfg_ready`). `CMD = 2` validates every
dirty table (Q entry 0 gives `ZERO_QUANT`; DHT rules of spec §6 give
`BAD_HUFFMAN`) and builds the lookups. A table that fails is marked invalid;
`CMD = 1` with any invalid or uncommitted table required by the mode raises
`TABLE_INVALID` and emits nothing. So a header can never replay bytes that
disagree with the lookups in force (spec §7). Reset loads the Annex K
defaults through the same path.

### 4. Stream graph and widths

```
host pix ─> [color_convert] ─24─> [downsample] ─40─> [mb_ctrl] ══M0══ (also read side)
                                                         │32+4
                                  [dct] <────────────────┘
                                    │ 21 (idx6+val15)
                              [zigzag C0/C1]
                                    │ 15+3
                                 [quant]  ──M1 (Q words)
                                    │ 12+3
                                  [huff]  ──M1 (DC, AC luma) ──M2 (AC chroma)
                                    │ 32+1
                                [bitpack] ─8+1─> [out_mux] ─> host byte out
 [cfg_regs]─>[table_load]─M1,M2   [header_gen] ─8+1─┘   ([qoi] ─8+1─┘ , M0 index)
```

| Stream | From to | Payload | Width |
|---|---|---|---|
| S0 | top to `color_convert` / `qoi` | `pix_data` | 8 |
| S1 | `color_convert` to `downsample` | `{Y, Cb, Cr}`, one per pixel (grey: Y only) | 24 |
| S2 | `downsample` to `mb_ctrl` | word write `{offset[6:0], word[31:0]}` | 39 |
| S3 | `mb_ctrl` to `dct` | one 32-bit M0 word (4 samples, lane = column mod 4) plus tag `{last, comp[1:0], first}`; 2 words per 8-sample row, 16 per block | 32 + 4 |
| S4 | `dct` to `zigzag` | `{natural_idx[5:0], coef[14:0]}` plus tag | 21 + 3 |
| S5 | `zigzag` to `quant` | coefficient in zig-zag order, 64 per block, plus tag `{last, comp[1:0]}` | 15 + 3 |
| S6 | `quant` to `huff` | quantized value, signed, zig-zag order, 64 per block, plus tag | 12 + 3 |
| S7 | `huff` to `bitpack` | `{len[4:0], bits[26:0]}`, code and additional bits right-justified, plus `last` (final symbol of the frame) | 32 + 1 |
| S8 | `bitpack`, `header_gen`, `qoi` to `out_mux` | byte plus `last` (per source: end of that segment) | 8 + 1 |

`comp` is 0 Y, 1 Cb, 2 Cr, and selects the quantization table and Huffman
tables downstream. The width of S6 is 12 bits because the quantized DC is at
most 11 bits of magnitude plus sign and an AC is clamped to +-1023 (spec §5);
S7 is 27 bits at most (16-bit code plus 11 additional bits for DC). Quasi-static
levels from `cfg_regs` (mode, true width and height, MCU count, a
`frame_active` level) are held constant from the start strobe to the end of
the frame and are not streams.

**Zig-zag position.** The coefficient reorder sits before the quantizer:
elementwise quantization commutes with the permutation, so the bytes are
unchanged, and the quantizer then reads the zig-zag-ordered Q tables of spec
§5 sequentially (one word per four coefficients, 16 per block) as record 0004
assumes.

**Symbol index for the lookup memories** (contract between `jc_table_load`
and `jc_huff`): AC index `10 * run + (size - 1)` for run 0 to 15, size 1 to
10 (0 to 159), `160` = EOB (`0x00`), `161` = ZRL (`0xF0`); DC index = size
(0 to 11). Entries are `{len[4:0], code[15:0]}` as in spec §13.

### 5. Memory access per stage

Instances and maps are spec §13 unchanged. Priority is fixed, highest first.

| Instance | Client (priority order) | Access | Per-MCU count (colour) |
|---|---|---|---|
| M0 | `mb_ctrl` write side (from `downsample`), then `mb_ctrl` read side (to `dct`); in QOI mode `qoi` instead (index read, conditional write) | write 1 word / read 1 word | 96 writes, 96 reads |
| M1 | `table_load` (idle only), `huff` (DC0, DC1, AC0 lookups), `quant` (Q words), `header_gen` (raw DQT/DHT bytes) | read; `table_load` also writes | Y block: 63 AC + 1 DC + 16 Q = 80; Cb or Cr block: 1 DC + 16 Q = 17; MCU: 4 x 80 + 2 x 17 = 354 |
| M2 | `table_load` (idle only), `huff` (AC1 lookups), `header_gen` (raw AC0, AC1 payload) | read; `table_load` also writes | Cb or Cr block: at most 63 AC; MCU: 126 |

Notes. (a) **M0 buffer layout.** Buffer base is word 0 (A) or 96 (B), toggled
per MCU. Colour, offset from base: Y(r,c) at `16 * (2r + c)`, Cb at 64, Cr at
80 (the §2 MCU order). Pixel `(py, px)` in the macroblock goes to word
`16 * (2 * (py >> 3) + (px >> 3)) + 2 * (py & 7) + ((px & 7) >> 2)`, lane
`px & 3`. Chroma sample `(cy, cx)` goes to word `64 + 16 * k + 2 * cy + (cx >> 2)`,
lane `cx & 3`, k = 0 Cb, 1 Cr. Grey: block j uses base A for even j, B for odd
j, words 0 to 15 of the buffer, word `2 * row + (col >> 2)`. (b) **Chroma
accumulator.** The vertical pair of the 2 x 2 average is held in
`downsample` as 8 columns x 2 components of 9-bit partial sums in registers
(record 0002); it is finished on odd pixel rows with the bias of spec §4
(1 for even output column, 2 for odd). (c) The write side has priority
because the host cannot be stalled mid-pixel without lowering `pix_ready`;
the read side prefetches one vector (two words) ahead so a delayed read
does not stall the DCT. (d) The header reads (lowest priority on M1/M2)
cannot deadlock the scan: `bitpack` holds the first scan byte until the
header is out, which stops `huff` and `quant` requesting, which frees the
port. (e) A violation of the priority rules by a client is a bug in that
client's issue.

### 6. DCT and buffers, in numbers

- `jc_dct1d` is one 8-point engine used for all 16 vectors of a block (8 rows,
  then 8 columns), with **two** 17 x 15-bit multipliers shared over the 12
  products of record 0003 (6 multiply cycles), at one vector per **8 cycles**.
  Pass 1 writes the transpose register file `jc_xpose_rf` (64 x 14, record
  0004); pass 2 reads a column and writes `{idx, coef}` to `jc_zigzag`.
- `jc_zigzag` holds **two** 64 x 15-bit standard-cell register files C0 and
  C1 (1920 flops). The DCT writes one while `quant` is fed from the other.
- Quantizer arithmetic: for `|x| <= 8192` and Q in 1..255,
  `floor((|x| + 4Q) / 8Q) = floor(((|x| + 4Q) >> 3) / Q)`, and the inner
  numerator is below 2^11, so a multiply by `ceil(2^19 / Q)` followed by `>> 19`
  gives the same quotient. Checked exhaustively for the second step (all Q,
  all numerators 0 to 1151) and on a stride of the first on 2026-10-27 with a
  throwaway script; the exhaustive check of the whole expression stays with
  #44 (spec §5). This is a hint to #44, not a mandate: a divider with
  throughput of one coefficient per cycle is equally acceptable.

### 7. Cycle budget

Budgets are per 4:2:0 MCU (6 blocks) at 50 MHz against the §9 figure
**1388.9 cycles/MCU** (231.5 per block). Stages overlap: M0 is double
buffered (record 0002), `zigzag` is ping-pong, and `quant` to `huff` to
`bitpack` run as a streaming chain. **Throughput of the pipeline is
therefore set by its slowest stage, not by the sum of the stages**; each row
must be at most 1388.9 and the shared-memory rows (last four) are the
sums that must also fit. The serial sum of all five stage rows (4241) is
reported only as the bound on first-MCU latency.

| Stage | Budget derivation | Cycles per MCU | % of 1388.9 |
|---|---|---|---|
| 1 Ingest, convert, downsample | input-bound: 3 beats x 256 pixels; §9 row "Input-bus cycles per MCU: 768 (55%)" | 768 | 55.3 |
| 2 M0 read, DCT (both passes) | per block 16 vectors x 8 cycles + 12 fill/drain = 140, 6 blocks; against §9 231.5 per block | 840 | 60.5 |
| 3 Zig-zag, quantize | 64 coefficients at 1 per cycle + 8 latency = 72 per block; against §9 231.5 per block | 432 | 31.1 |
| 4 Huffman symbol path | Y block: 80 M1 accesses x A = 160 + 10 fill = 170; Cb/Cr block: 63 M2 accesses x 2 = 126 + 10 = 136 (Q reads on M1 overlap); 4 x 170 + 2 x 136; M1 count from record 0004 | 952 | 68.5 |
| 5 Bit pack and byte out, **worst-case content** | 6 x 1665 bits (§3 per-block bound) = 9990 bits = 1248.75 bytes at 1 byte per cycle; §3 "44.96 MB/s under 50 MB/s" | 1249 | 89.9 |
| M0 port | (96 writes + 96 reads) x A = 2; §9 "192 port cycles", worst tolerable A is 7 | 384 | 27.6 |
| M1 port | 354 accesses x 2 | 708 | 51.0 |
| M2 port | 126 accesses x 2 | 252 | 18.1 |

**Slowest stage.** At worst-case content (`noise_max_entropy_640x480`,
spec §12) it is **stage 5, the bit packer and one-byte output**, at 1249
cycles/MCU, because the output is one byte per cycle (spec §3 sizes it at 90% of
the port). At typical content (`scene_fbm_640x480`) the scan output is far
below its bound and the slowest stage is **stage 2, the DCT**, at 840.
Neither figure is a result; the cycles per frame are counted in simulation on
those images (item 5).

**Frame bound at the target (derived from the budgets).** 1200 MCUs x 1249 =
1,498,800 cycles at worst-case content, plus first-MCU latency 4241 and the
header 627 bytes (625 + `EOI`, spec §7) = 1,503,668 cycles, which is 90.2%
of the frame period 50e6 / 30 = 1,666,667. The same bound at 840 cycles/MCU
is 1,012,868 (60.8%).

Other modes against §9:

| Mode | Requirement (§8, §9) | Budget | Verdict |
|---|---|---|---|
| Grey 320 x 240, 25 MHz | 1388.9 cycles per block | slowest stage the packer, 1665 bits / 8 = 209 per block; DCT 140; ingest 64 | 15.0% of the budget, met |
| QOI 640 x 480, 50 MHz | 5.43 cycles per pixel; input 3, output at most 4 | `jc_qoi` at most 4 cycles per pixel (index read A = 2, conditional write A = 2; input 3 beats; output at most 4 bytes) | 73.7%, met by budget |
| Colour 1280 x 720, 100 MHz (stretch) | 925.9 per MCU, 154.3 per block | DCT 840 (90.7%) and ingest 768 (83.0%) fit; stage 4 (952) and stage 5 (1249) **do not** at worst-case content | not met at worst case; stretch is open for typical content only, to be decided by item 8 |

### 8. Edge cases in the stage graph

- **Grey**: `color_convert` forwards the byte as Y, `downsample` only packs
  4 samples per word (no chroma accumulator), `mb_ctrl` alternates buffers
  per block, `dct` runs one block per MCU, `zigzag` and `quant` use comp 0,
  `huff` uses DC0/AC0 only, `header_gen` emits one DQT, one SOF0 component,
  DC0 and AC0 DHT only (spec §7). The `last` tag is on every block's final
  coefficient only for the frame's last block.
- **QOI**: `pix_data` goes to `jc_qoi` (it assembles R, G, B beats), `mb_ctrl`
  and everything between `color_convert` and `bitpack` are idle, `qoi` uses
  M0 words 192 to 255 only, `header_gen` emits the 14-byte header and the
  8-byte end marker, `out_mux` takes bytes from `qoi` between them.
- **Non-multiple sizes**: the chip is unaware of padding (spec §2); it counts
  padded pixels for ingest and writes the true `W`, `H` into SOF0 or the QOI header.

## Rejected alternatives

- *Single coefficient buffer after the DCT.* The buffer would be held until
  the Huffman stage has consumed block n, and the DCT of block n+1 writes it
  only after that: block period at worst-case content is at least
  170 + 70 (pass 2) = 240 cycles, above the 231.5 per block of §9. Ping-pong
  removes the coupling for 960 flops.
- *Merging the transpose file and the coefficient buffers (in place, two
  64 x 15 files).* Saves about 900 flops but changes the 64 x 14 transpose
  memory that spec §13 and record 0004 ratify; that needs its own record.
- *Quantizing in natural order as the DCT emits columns.* Needs a Q entry
  per coefficient: 64 reads per block instead of 16, so M1 would see 144
  accesses on a Y block, 288 cycles at A = 2, above 231.5.
- *One-byte configuration writes with no handshake.* Would need a staging
  word per table window or byte enables of unknown width; `cfg_ready` with a
  read-modify-write costs nothing at table-load rates (412 bytes).
- *A second DCT engine, or more multipliers.* The 140 cycles per block use
  60.5% of the budget, so extra area buys no row of the target; the stretch is
  limited by stages 4 and 5, not by the DCT.
- *Register-read status bus.* The pins `status_*` and `err_cause` meet "error
  cause readable" with no read channel to verify.

## Consequences

- **Interface freeze.** Ports, stream widths, the address map, the error
  codes, the symbol index and the M0 layout above are the contract for #42 to
  #48. A stage that needs to change one files a new record; it does not
  edit this one or the spec.
- **No ratified spec text is changed.** This record adds the two coefficient
  buffers C0 and C1, which §13 does not mention (it names only the transpose
  file); they are standard-cell register files, no macro. Spec §13's
  statement is unchanged.
- **Table errors are a state, not an atomic reject.** A failed commit leaves
  the raw bytes overwritten and the table marked invalid (`TABLE_INVALID` at
  start), instead of restoring the previous table. If #46 wants restore, it
  needs double raw storage and a new record.
- **Stretch.** At worst-case content stages 4 and 5 exceed 925.9 cycles/MCU
  (table above); this is a derived finding for item 8, not a claim about the
  stretch.
- **A = 2 is unverified.** Until the macro's Liberty views exist (record 0004
  gate), rows using A are budgets under an assumption.
- **Verification.** Each stage issue states which row of section 7 its
  testbench checks and counts the cycles in simulation. The golden model
  (#34) does not depend on this record: bytes are fixed by spec §4 to §7.
