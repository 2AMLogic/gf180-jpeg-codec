# Decision record 0002: block-ordered input, one double-buffered macroblock

**Status**: Decided, 2026-10-17
**Resolves**: the input-order, buffering and host-interface rows of #3
**Spec**: `spec/codec.md` §3 and §13

## Question

4:2:0 coding works on 16-line strips. Does the chip take raster input and
buffer a strip, or take block-ordered input and buffer one macroblock? The
choice sets the memory, the floorplan and the host interface.

## Memory for both options (derived)

Formulas: a stored 4:2:0 sample set is Y (1 byte/pixel) plus Cb and Cr (one
byte per 2 x 2 pixels each), so 1.5 bytes/pixel; raw RGB is 3 bytes/pixel.
The `gf180-sram` macro is 256 x 32 = 1024 bytes (`spec/sram.md`, in that
repo). The foundry `gf180mcu_fd_ip_sram__sram512x8m8wm1` is 512 bytes,
431.86 x 484.88 um = 0.2094 mm² (read from the LEF by `gf180-sram`'s
`spec/kb-scale-integration.md`).

| Option | Bytes | `gf180-sram` macros | Foundry 512 B macros (footprint only) |
|---|---|---|---|
| Raster strip, 640 wide, 16 lines, converted, 4:2:0 | 640 x 16 x 1.5 = **15,360** | 15 | 30 = 6.28 mm² |
| Raster strip, raw RGB | 640 x 16 x 3 = 30,720 | 30 | 60 |
| Raster strip, 4:2:0, double-buffered | 30,720 | 30 | 60 |
| One 16 x 16 macroblock, 4:2:0 | 16 x 16 x 1.5 = **384** | 1 (38%) | 1 |
| Macroblock, double-buffered | **768** | **1 (75%)** | 2 |

A strip is more than an order of magnitude beyond one macro, as `CLAUDE.md`
warned. A double-buffered macroblock fits one macro with 256 bytes to spare.

## Decision

**Block-ordered input**: the host supplies 16 x 16 macroblocks (grey: 8 x 8
blocks) and the chip buffers one macroblock **double-buffered** (two 384 B
buffers, 192 words) in one `gf180-sram` instance. Details in
`spec/codec.md` §3.

Rejected alternatives:

- *Raster input with a strip buffer*: the 15 to 60 macros in the table, a
  floorplan dominated by memory, and an on-chip reorder that the host's own
  frame store makes unnecessary. This is the option `CLAUDE.md` calls the
  central risk, taken off the chip.
- *Block-ordered, single-buffered*: ingest (768 beats per macroblock at 8 bits
  and 3 beats/pixel) and encode would run serially. Against the target budget
  of 1388.9 cycles per MCU (`spec/codec.md` §9), the encode time would have to
  fall to 1388.9 - 768 = **620.9 cycles**, 2.2 times tighter, for 38% of one
  macro saved.
- *Hybrid (raster in, internal strip of fewer lines)*: 4:2:0 and the 8 x 8
  DCT need 16 lines; fewer lines cannot form an MCU.

## Consequences

- **The cost moves to the host.** A host with a raster source (a frame store,
  a camera) must reorder into macroblocks, which needs its own strip or frame
  storage. The host is outside this project's scope (`CLAUDE.md`: no
  processor, no camera or display interface), so this is accepted and stated
  here, not hidden. A system that cannot reorder cannot use this chip's JPEG
  path.
- **QOI is raster by nature** (spec §8) and needs no buffer, so the block-order
  decision does not affect it; the host sends QOI pixels in image order.
- **Port arbitration.** One 1RW port serves the ingest writes and the encode
  reads: 192 port cycles per MCU (spec §9), 14% of the target budget and 21%
  of the stretch budget, so a single port suffices if the macro completes an
  access in at most 7 cycles (target) or 4 (stretch).
- **Greyscale needs its own order** (8 x 8 blocks in raster block order),
  because a single-component scan is not MCU-grouped.
- A conversion pipeline that downsamples chroma on ingest needs a one-row
  accumulator for the vertical pair of the 2 x 2 average: 8 chroma columns x
  2 components of partial sums, in registers.
