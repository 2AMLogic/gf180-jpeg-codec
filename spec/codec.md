# Target spec: gf180mcu baseline-JPEG + QOI encoder

**Status**: Ratified, 2026-10-17
**Resolves**: #3 ("Draft and ratify the target spec")
**Decision records**: [0002 input order and buffering](decision-records/0002-input-order-and-buffering.md),
[0003 DCT arithmetic](decision-records/0003-dct-arithmetic.md),
[0004 SRAM source](decision-records/0004-sram-source.md). The PDK pin is
`decision-records/0001-pdk-pin.md`, owned by #5; this spec cites it and does
not restate it.

This turns the README's DRAFT table into the spec agents build and verify
against. Per `CLAUDE.md` it is not relaxed to make a result pass: a change to
any ratified row needs a new decision record, not an edit against a failing
result. Every parameter is either **ratified** (a value) or **deferred**
(a reason and the issue that settles it). Nothing here relaxes a `CLAUDE.md`
constraint.

Evidence tiers used below: **derived** = arithmetic from stated formulas
(reproducible from this page); **measured** = read from a tool or file on
2026-10-17 on the stated host; **exploratory** = run once, script not
committed, to be repeated by the issue that owns the golden model.

## 1. README table, row by row

| README row | Target | Fallback | Stretch | Disposition |
|---|---|---|---|---|
| JPEG mode | baseline sequential, YCbCr 4:2:0, 8-bit | baseline, greyscale (1 component) | + baseline decoder | Target and fallback **ratified** (§2). Stretch decoder **deferred**: not designed until the encoder closes (`CLAUDE.md`); owner #4 (tracker), to be split out when item 5 closes. |
| Lossless path | QOI encoder | none | + QOI decoder | Encoder **ratified** (§8). Decoder **deferred**, same reason and owner. |
| Resolution / rate | 640 x 480 at 30 frames/s | 320 x 240 at 15 frames/s | 1280 x 720 at 30 frames/s | **Ratified** with derived budgets (§9). |
| Tables | runtime-loadable quantization and Huffman | fixed standard tables | none | **Ratified** (§5, §6): loadable in the target, Annex K defaults loaded by reset in the fallback. |
| Signoff clock (post-route STA, slow corner) | 50 MHz | 25 MHz | 100 MHz | **Ratified** (§10). Whether each is *closed* is evidence, owned by #4 items 5 and 8. |
| Correctness | byte-exact vs software golden encoder | none | none | **Ratified** (§11). |
| Signoff | DRC + LVS clean, STA closed at every ratified corner | none | none | **Ratified**: corner list in §10; DRC/LVS evidence owned by #4 items 3 and 4. |

Maturity-ladder position after this spec: **spec ratified**; the golden model
is next (§11, §12).

## 2. Modes and colour format

| Parameter | Ratified value |
|---|---|
| JPEG process | Baseline sequential DCT (SOF0), 8-bit samples, Huffman, one scan, interleaved |
| Colour modes | **Colour**: 3 components Y, Cb, Cr at 4:2:0 (Y sampling 2 x 2, Cb and Cr 1 x 1). **Grey**: 1 component, sampling 1 x 1 |
| 4:4:4 and 4:2:2 | **Not supported** (non-goal). Rejected alternative: a sampling-factor register; it multiplies the MCU shapes, the buffer layouts and the golden-model cases for no row in the README |
| Input colour | 24-bit RGB (colour mode) or 8-bit luma (grey mode). YCbCr input is not supported |
| Image size | Width and height programmable, 16-bit each (1 to 65535) |
| Non-multiple sizes | The host pads to a whole MCU (16 x 16 colour, 8 x 8 grey) by replicating the last column and last row. The chip emits the true size in SOF0 and is unaware of padding. The edge rule is part of the golden model's reference-image cases (§12) |
| Restart markers | **Not supported**: no DRI, no RSTn. Rejected alternative: a restart-interval register. Baseline decodability does not need it, and it adds a bit-alignment and predictor-reset path to verify |
| Progressive, arithmetic, 12-bit | Out of scope (`CLAUDE.md`) |

MCU order in colour mode is Y(0,0), Y(0,1), Y(1,0), Y(1,1), Cb, Cr, where
Y(r,c) is the 8 x 8 luma block at row r, column c of the 16 x 16 macroblock.
Grey mode has one 8 x 8 block per MCU. MCUs are in raster order over the
image.

## 3. Input order and host interface

Ratified in [decision 0002](decision-records/0002-input-order-and-buffering.md):
**block-ordered input**. The host reorders; the chip buffers one macroblock
(double-buffered), never a strip.

- **Colour mode**: the host sends 16 x 16 macroblocks in raster macroblock
  order. Inside a macroblock the 256 pixels are in raster order (16 per row),
  each pixel as three bytes R, G, B. One macroblock is 768 bytes.
- **Grey mode**: the host sends 8 x 8 blocks in raster block order, 64 bytes
  per block, pixels in raster order inside the block. (A single-component
  scan is ordered by block raster across the image, T.81 A.2.2, so a 16 x 16
  grouping would not match the scan order.)
- **QOI mode**: the host sends pixels in image raster order, as R, G, B bytes
  (§8).

The host interface is specified by behaviour; pin-level definition belongs to
the RTL architecture issue (owner #4 item 1).

| Port | Required behaviour |
|---|---|
| Pixel input | 8-bit data, valid/ready. 3 beats per pixel in colour and QOI mode, 1 per pixel in grey mode |
| Byte output | 8-bit data, valid/ready, `last` on the final byte of the file. Emits a complete file: JFIF/JPEG (§7) or QOI (§8) |
| Configuration and table load | Mode, width, height, and the table payloads of §5 and §6 in JPEG segment byte format. Loading is allowed only while idle; a violating write sets an error flag and changes nothing |
| Status | idle / busy / error, with the error cause readable |

**Back-pressure**: the output is back-pressured; the datapath stalls and
nothing is dropped. The chip never buffers a frame. The input is also
back-pressured (`ready` low while the next macroblock buffer is still being
encoded).

**Worst-case output per frame** (derived). Per 8 x 8 block, with tables whose
codes are at most 16 bits and AC sizes at most 10: DC at most 16 + 11 = 27 bits,
each of 63 AC coefficients at most 16 + 10 = 26 bits, so 27 + 63 x 26 =
**1665 bits** per block. The 4:2:0 640 x 480 frame has 7200 blocks:
7200 x 1665 = 11,988,000 bits = **1,498,500 bytes** before byte stuffing. Byte
stuffing (§7) at most doubles the scan, an unreachable bound that the
interface must tolerate through back-pressure and not through sizing. The
header is at most 625 bytes (§7). At 30 frames/s the pre-stuffing worst case is
44.96 MB/s, under the 50 MB/s of a byte per cycle at 50 MHz.

## 4. Colour conversion

Ratified: RGB to YCbCr on chip, in the integer form of libjpeg's `jccolor.c`
(SCALEBITS = 16). Constants `FIX(x) = floor(x * 65536 + 0.5)`:

| Constant | Value |
|---|---|
| FIX(0.29900), FIX(0.58700), FIX(0.11400) | 19595, 38470, 7471 |
| FIX(0.16874), FIX(0.33126), FIX(0.50000) | 11059, 21709, 32768 |
| FIX(0.41869), FIX(0.08131) | 27439, 5329 |

```
Y  = ( 19595*R + 38470*G +  7471*B + 32768)                       >> 16
Cb = (-11059*R - 21709*G + 32768*B + (128<<16) + 32768 - 1)       >> 16
Cr = ( 32768*R - 27439*G -  5329*B + (128<<16) + 32768 - 1)       >> 16
```

`>>` is an arithmetic shift (floor). R, G, B are unsigned 8-bit. Every
intermediate fits a signed 25-bit word (the largest is 32768*255 + 128*65536 +
32767 < 2^24). **No saturation is needed**: all 2^24 RGB inputs were run and
Y, Cb, Cr stay within 0..255 (measured, 2026-10-17).

Worked examples (derived by the formulas above):

| R, G, B | Y | Cb | Cr |
|---|---|---|---|
| 255, 0, 0 | 76 | 85 | 255 |
| 12, 200, 77 | 130 | 98 | 44 |
| 255, 255, 255 | 255 | 128 | 128 |
| 0, 0, 0 | 0 | 128 | 128 |

**4:2:0 downsampling** (libjpeg `h2v2_downsample`, smoothing off): each chroma
sample is the sum of the 2 x 2 co-sited converted samples plus a bias, shifted
right by 2. The bias alternates along each output row by output column index
j: **1 when j is even, 2 when j is odd**. Example: samples 200, 201, 202, 205,
j even: (808 + 1) >> 2 = 202. Samples 10, 11, 12, 13, j odd: (46 + 2) >> 2 = 12.
Conversion happens before downsampling, on the full-resolution planes.

In grey mode the input byte is Y and there is no conversion.

## 5. Quantization

- Two tables, indexed 0 (luma) and 1 (chroma). Each holds 64 entries, 8-bit
  precision, value 1 to 255, loaded in the **DQT payload byte order (zig-zag)**.
  An entry of 0 is rejected as a load error.
- **Target**: runtime-loadable. **Fallback**: Annex K tables (Table K.1 luma,
  K.2 chroma), the reset default, loadable-over. Annex K scaled to a quality
  setting is a host-side choice; the chip sees only the 64 bytes.
- Rounding, for a DCT output x (§6 of record 0003) and entry Q:

```
D = 8 * Q
q = sign(x) * floor((|x| + (D >> 1)) / D)        # round half away from zero
```

  The factor 8 undoes the 8x output scale of the DCT. The RTL may use a
  divider or a reciprocal multiply, but its result must equal this expression
  for every |x| <= 8192 and every Q in 1..255: an exhaustive check, owned by
  the RTL issue (#4 item 5).
- **Saturation**: the quantized DC value needs no clamp (at most 11 bits of
  magnitude for the DC difference, size category 11). After quantization an AC
  value is **clamped to [-1023, 1023]**, the largest magnitude of size
  category 10. The clamp can act only at Q = 1 at the extreme of the input
  range, because the true AC maximum is 1024 to within 1e-12 (derived by
  summing the cosine products over the +-128 input range). The golden model
  counts every clamp and the reference-image evidence records that count.

Worked example, the 8 x 8 block of record 0003 (first two rows of the
coefficient array, row-major, `D = 8*Q` with the Annex K luma table):

```
DCT output   -3323 -241 -489  218  449 -160  -19    4 |  36 -174 -486   82  105  -57  -68   39
Q (natural)     16   11   10   16   24   40   51   61 |  12   12   14   19   26   58   60   55
q                -26   -3   -6    2    2   -1    0    0 |   0   -2   -4    1    1    0    0    0
```

(For example -3323: D = 128, (3323 + 64) / 128 = 26.46, floor 26, sign gives
-26.)

## 6. Zig-zag, DC prediction, Huffman coding

Zig-zag scan order (T.81 Figure A.6), natural index (row*8 + column) for each
zig-zag position 0..63:

```
 0  1  8 16  9  2  3 10 17 24 32 25 18 11  4  5
12 19 26 33 40 48 41 34 27 20 13  6  7 14 21 28
35 42 49 56 57 50 43 36 29 22 15 23 30 37 44 51
58 59 52 45 38 31 39 46 53 60 61 54 47 55 62 63
```

- **DC**: difference to the previous block **of the same component** in scan
  order; predictors reset to 0 at the start of the scan (no restarts). The
  difference is coded as a size category (0 to 11) through the DC table, then
  `size` additional bits.
- **AC**: for each non-zero coefficient after position 0: symbol
  `(run << 4) | size` through the AC table, then `size` additional bits;
  runs of 16 or more zeros emit ZRL (`0xF0`) once per 16; if zeros remain after
  the last non-zero coefficient emit EOB (`0x00`); a block whose position 63 is
  non-zero emits no EOB.
- **Additional bits**: for value v of size s, the low s bits of v for v >= 0
  and of `v + 2^s - 1` for v < 0.
- **Table assignment**: luma blocks use DC table 0 and AC table 0; Cb and Cr
  use DC table 1 and AC table 1 (grey uses table 0 only).
- **Tables**: four tables, each loaded as a DHT payload
  (`BITS[1..16]`, then `HUFFVAL`). Canonical code assignment is T.81 Annex C.
  **Target**: runtime-loadable. **Fallback**: Annex K.3 tables, the reset
  default. The loader rejects a table whose DC symbols exceed 11, or whose AC
  symbols are not among the 162 valid baseline symbols (run 0..15 with size
  1..10, plus `0x00` and `0xF0`), or whose code lengths exceed 16. The 162 limit is
  what lets the lookup memory be sized exactly (§13).
- **Packing**: codes are written MSB first into a bit accumulator; every byte
  `0xFF` is followed by `0x00`; the last partial byte is padded with 1 bits.

Worked example: the §5 block alone in a grey scan, Annex K luma tables. The DC
difference is -26: size 5, DC code `110`, additional bits `00101`. The AC
symbols in order: `0x02` (`01`, bits `00`), `0x12` (`11011`, bits `00`),
`0x02`, `0x03` (`100`), and so on to `0x51` (`1111010`) for the run of five zeros before
the last `-1`, ending with `0x00` EOB (`1010`). The packed scan is the 12
bytes `c54d8b0b4650994b021bd057`. Exploratory cross-check: Pillow 10.2.0
(libjpeg-turbo 2.1.5) at quality 50 produces the identical entropy-coded
segment for this block.

## 7. Output framing

Ratified: **the chip emits the complete file**; the host does not touch the
byte stream. Rejected alternative: host-supplied headers, because it moves
the table and size serialization off chip and so leaves the byte-exact check
covering only the scan, which is the weaker claim.

Segment order and content (read from a libjpeg-turbo 2.1.5 file, measured
2026-10-17): `SOI` (`FFD8`); `APP0` JFIF (`FFE0`, length 16, `JFIF\0`, version
1.01, units 0, X and Y density 1, no thumbnail); one `DQT` segment per table
(`FFDB`, length 67, Pq = 0, Tq = index, 64 bytes); `SOF0` (`FFC0`, P = 8, Y, X,
then components); `DHT` per table in the order DC0, AC0, DC1, AC1 (`FFC4`);
`SOS` (`FFDA`); the scan; `EOI` (`FFD9`).

| Mode | SOF0 components (id, sampling, Tq) | SOS (id, Td/Ta) |
|---|---|---|
| Colour | (1, `0x22`, 0), (2, `0x11`, 1), (3, `0x11`, 1) | (1, `0x00`), (2, `0x11`), (3, `0x11`), Ss 0, Se 63, Ah/Al 0 |
| Grey | (1, `0x11`, 0) | (1, `0x00`), Ss 0, Se 63, Ah/Al 0; DQT 0 and DHT DC0, AC0 only |

The DQT and DHT segments **replay the loaded payload bytes verbatim**, so the
loaded table and the emitted table cannot disagree. Header size, colour mode,
worst case: 2 + 18 + 2 x 69 + 19 + (2 x 183 + 2 x 33) + 14 + 2 = **625 bytes**
(AC DHT: 4 + 1 + 16 + 162 = 183; DC DHT: 4 + 1 + 16 + 12 = 33).

## 8. Lossless path (QOI)

- **Target**: QOI encoder per the QOI specification (version 1.0), 3
  channels, colourspace 0 (sRGB with linear alpha), no alpha. The output is a
  complete `.qoi` file: 14-byte header, chunks, and the 8-byte end marker.
  **Stretch**: decoder, **deferred** (see §1).
- **Input order**: image raster. QOI codes against the previous pixel and a
  64-entry running index, so it needs no strip or macroblock buffer; a
  non-raster order would produce a valid but non-standard stream.
- **Buffer sharing**: QOI **does not share** the JPEG macroblock buffer. It
  shares the pixel input port, the byte output port and the macroblock-buffer
  SRAM instance, in a disjoint region (§13): its 64-entry index sits in 64
  words that the JPEG buffer does not use. Mode is per frame and exclusive.
- Worst case output (derived): the 4-byte `QOI_OP_RGB` chunk per pixel, so
  640 x 480 x 4 + 14 + 8 = **1,228,822 bytes**; 36.9 MB/s at 30 frames/s.
- Throughput (derived): 640 x 480 x 30 = 9,216,000 pixels/s, so
  50 MHz / 9,216,000 = **5.43 cycles/pixel**. Input needs 3 beats/pixel and
  the worst output is 4 bytes/pixel, both within 5.43.
- Golden model: a committed port of the reference encoder (§11).

## 9. Throughput

Budget = signoff clock / (samples or blocks per second). The cycles are for
the whole encoder, so they are an upper bound for the slowest stage of the
pipeline.

| | Target | Fallback | Stretch |
|---|---|---|---|
| Format | 640 x 480, 4:2:0 | 320 x 240, grey | 1280 x 720, 4:2:0 |
| Samples/frame | 460,800 | 76,800 | 1,382,400 |
| Frames/s | 30 | 15 | 30 |
| Samples/s | 13,824,000 | 1,152,000 | 41,472,000 |
| MCUs/frame | 1200 | 1200 | 3600 |
| MCUs/s | 36,000 | 18,000 | 108,000 |
| Signoff clock | 50 MHz | 25 MHz | 100 MHz |
| **Cycles per sample** | **3.617** | **21.70** | **2.411** |
| **Cycles per MCU** | **1388.9** | **1388.9** | **925.9** |
| Cycles per 8 x 8 block | 231.5 | 1388.9 | 154.3 |
| Input-bus cycles per MCU | 768 (55%) | 64 (4.6%) | 768 (83%) |

Samples/frame is width x height x 1.5 for 4:2:0 and width x height for grey.
Cycles per sample = clock / samples per second. The input-bus row is
3 beats x 256 pixels (colour) or 1 beat x 64 pixels (grey) against cycles per
MCU. At the stretch row 83% of the budget is input beats; the stretch is
feasible only if the host never stalls the input.

**Frame rates are claims about the signoff clock and counted cycles.** A
frame-rate figure in any later document must be derived as
`signoff clock / cycles per frame`, with cycles per frame counted in
simulation on a named image from §12 (`noise_max_entropy_640x480` is the
worst case, `scene_fbm_640x480` the typical case). A simulated number is never
called measured.

Memory-port budget (derived, input to decision 0004): per MCU the macroblock
buffer sees 96 word writes and 96 word reads (384 samples at 4 per word), so
192 port cycles. The largest tolerable macro access latency, if every access
costs the same, is `floor(cycles per MCU / 192)` = **7** cycles at the target
and **4** at the stretch.

## 10. Signoff clock, library, supply and corners

**Library**: `gf180mcu_fd_sc_mcu9t5v0`, variant `gf180mcuD` (PDK pin in
`0001-pdk-pin.md`, #5). Ratified; matches the provisional choice in #5. The
7-track library `gf180mcu_fd_sc_mcu7t5v0` is installed alongside and was not
evaluated: it is denser and was not needed to reach a 50 MHz target. A switch
needs a decision record backed by synthesis results.

**Supply**: a single 3.3 V rail, nominal. Rejected alternative: 5 V
operation, because the SRAM macro (the one non-standard-cell block) is
ratified at 3.3 V only.

**Signoff clock** (post-route STA, setup at the slow view `ss_125C_3v00`):
50 MHz target, 25 MHz fallback, 100 MHz stretch.

**STA views** (read from the installed library directory, measured
2026-10-17; the 9-track library has 15 PVT views, five are used):

| Role | Liberty file (`gf180mcu_fd_sc_mcu9t5v0__<view>.lib`) | Process | Temp | Standard-cell V |
|---|---|---|---|---|
| Setup, worst | `ss_125C_3v00` | ss | 125 C | 3.00 |
| Setup, cold-slow | `ss_n40C_3v00` | ss | -40 C | 3.00 |
| Typical | `tt_025C_3v30` | tt | 25 C | 3.30 |
| Hold, cold-fast | `ff_n40C_3v60` | ff | -40 C | 3.60 |
| Hold, hot-fast | `ff_125C_3v60` | ff | 125 C | 3.60 |

Setup is checked at all five, hold at all five; "STA closed at every ratified
corner" means these five.

**Reconciliation with `gf180-sram`.** The macro is ratified at 27 corners:
{ff, tt, ss} x {-40, 25, 125 C} x {2.97, 3.30, 3.63 V}. The standard-cell
library has no 2.97 V or 3.63 V view; its edges are 3.00 V and 3.60 V. Rule:
in each STA view above, the macro is read at the **same process and
temperature** and at the voltage that brackets the standard-cell voltage from
outside, so the mismatch is pessimistic for the check it matters to: 2.97 V in
the ss views (slower macro, setup), 3.63 V in the ff views (faster macro, hold),
3.30 V in tt. This is an approximation by construction and is recorded as
such; the rest of the 27 macro corners are not used for chip STA. Open until
the macro's Liberty views exist: they do not yet (gf180-sram README,
2026-10-17), so the macro is **unverified** at these views. Owner: the
`gf180-sram` Liberty issue, tracked here by #4 item 5.

## 11. Correctness: golden model

- **Golden JPEG model**: a software encoder committed in this repo at
  `verification/golden/jpeg_golden.py`, standard library only, **integer
  arithmetic throughout (no floating point)**, implementing §2 to §7 and the
  arithmetic of record 0003. The golden model is this repo's own code, not a
  library call: the RTL is compared to it, and libjpeg-turbo is the
  independent check beside it, not a substitute.
- **Golden QOI model**: `verification/golden/qoi_golden.py`, a line-for-line
  port of the reference encoder `qoi.h` (phoboslab/qoi, MIT) at a commit
  pinned in the golden-model issue.
- **How the arithmetic is made to match the RTL**: record 0003 fixes every
  width, constant, shift and rounding rule; the RTL must satisfy the text, and
  the golden model implements the same text. A disagreement is a bug in
  whichever side departs from the text.
- **Independent cross-checks** (a pass needs both):
  1. *Decodability*: every golden and RTL file decodes without error or
     warning in a reference decoder, **Pillow 10.2.0** (bundles libjpeg-turbo;
     `PIL.features.version("libjpeg_turbo")` reported 2.1.5 on 2026-10-17;
     every evidence record stamps the reported version). For QOI the reference
     decoder is `qoi.h` itself.
  2. *Arithmetic*: with the standard Annex K tables, the entropy-coded segment of
     a golden file equals the segment libjpeg-turbo writes for the same input
     (Pillow `save(..., quality=Q, subsampling=2)` for colour, `mode "L"` for
     grey, `optimize=False`). Header bytes differ in density metadata only if
     Pillow is configured otherwise and are not compared.
- **Exploratory result** (not committed evidence): on 2026-10-17 a throwaway
  integer model of §4 to §6 reproduced the libjpeg-turbo 2.1.5 scan bytes on 9
  of 9 trials: five greyscale (including 16 x 8 and 24 x 16 images, qualities
  10 to 90, one with `0xFF` stuffing) and four colour 4:2:0 (32 x 16 and
  48 x 32, qualities 30 to 95). It also reproduced the quantized coefficients
  of the T.81-style example block in §5. The golden-model issue must redo
  this as committed, scripted evidence.
- **Statistical rows**: none. The block is digital and every row of this spec
  is deterministic and exact, so Monte Carlo evidence (T1 item 6) is not
  applicable. This statement covers: JPEG mode, lossless path, resolution/rate
  (a derived cycle count), tables, signoff clock and byte-exactness, the last
  of which is exact by definition.

## 12. Reference image set

All images are **generated by a committed script**
(`verification/images/gen_images.py`, owned by the golden-model issue) under
the repo's Apache-2.0 licence, so no per-image third-party licence applies.
The generator is deterministic and integer-only; the PRNG is xorshift32
(shifts 13, 17, 5) with state seeded `0x1BADB002`, one step per byte, the byte
taken as the top 8 bits of the new state. The generated files' SHA-256 values
are committed beside the script and checked in CI.

| Name | Content | Why |
|---|---|---|
| `flat_gray_128`, `flat_white`, `flat_black` | constant | DC-only blocks; all-ZRL-free path; clamp absent |
| `ramp_h`, `ramp_v` | linear ramps in R, G, B | smooth, long zero runs |
| `checker_1px`, `checker_8px` | black and white | Nyquist AC; maximum high-frequency energy |
| `colour_bars` | saturated primaries and secondaries | colour-conversion extremes |
| `noise_max_entropy` | PRNG bytes in R, G, B | worst-case output (§3), stuffing, long codes |
| `scene_fbm` | integer value-noise sum, 5 octaves, natural-looking edges | typical compression and the typical-case cycle count |
| `odd_100x60` | `scene_fbm` cropped | non-multiple size, host padding rule (§2) |

Each is generated at **640 x 480** (frame-rate claims, §9), **64 x 48** (fast
CI simulation) and **16 x 16** (one macroblock); grey versions of the first
three sizes use the luma of the colour image from §4. Real photographs are
**not ratified**: if added, each needs a recorded licence (CC0 or public
domain), source URL and SHA-256 in `verification/images/LICENSES.md` before
it can appear in evidence.

## 13. Memory

Ratified in [decision 0004](decision-records/0004-sram-source.md): **adopt
`gf180-sram`'s 256 x 32 1RW macro** (`spec/sram.md`, ratified 2026-08-05),
three instances; no SRAM is designed here. Fallback and gate are in the record.

| Instance | Words (32 bit) | Contents |
|---|---|---|
| M0 | 0 to 95 | macroblock buffer A (384 B, 4:2:0) |
| | 96 to 191 | macroblock buffer B |
| | 192 to 255 | QOI index, 64 x 32 bit (R, G, B, 255) |
| M1 | 0 to 161 | AC luma code lookup (162 symbols; `{len[4:0], code[15:0]}`) |
| | 162 to 173 | DC luma lookup (12) |
| | 174 to 185 | DC chroma lookup (12) |
| | 186 to 217 | quantization tables, 2 x 64 B (32 words) |
| | 218 to 224 | DC0 raw DHT payload, 28 B (7 words) |
| | 225 to 231 | DC1 raw DHT payload (7 words) |
| M2 | 0 to 161 | AC chroma code lookup (162) |
| | 162 to 206 | AC0 raw DHT payload, 16 + 162 = 178 B (45 words) |
| | 207 to 251 | AC1 raw DHT payload (45 words) |

Total **740 words** of 768 are allocated (M0 256, M1 232, M2 252; 28 spare
in M1 and M2). The QOI index and the JPEG buffers are never live together, but
the map does not overlap them. The DCT transpose memory (64 x 14 bit) is a standard-cell register
file, not a macro (decision 0004).

## 14. Deferrals

| Item | Reason | Owner |
|---|---|---|
| Baseline decoder, QOI decoder (stretch) | `CLAUDE.md`: decoder does not drive the architecture before the encoder closes | #4, split out after item 5 closes |
| Macro Liberty/LEF at chip STA views; macro access latency against §9 | the views do not exist yet | `gf180-sram` Liberty work; consumed at #4 item 5 |
| Pin-level host interface, micro-architecture, pipeline stage split | RTL, after this spec | #4 item 1 |
| Whether 50 / 25 / 100 MHz *close* | evidence, not spec | #4 items 5, 7, 8 |
| `reuse.lock.json` | created when the macro is pinned; absent on `cf4e861` | the issue that integrates the macro |
| `0001-pdk-pin.md` | PDK pin | #5 |
