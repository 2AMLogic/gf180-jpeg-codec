# Decision record 0003: DCT arithmetic, bit for bit

**Status**: Decided, 2026-10-17
**Resolves**: the DCT and fixed-point rows of #3
**Spec**: `spec/codec.md` §4 to §6 use this record's arithmetic.

## Question

Which forward DCT, with which word lengths, rounding and shifts, so that the
golden model and the RTL agree exactly?

## Decision

Use the **accurate integer DCT of libjpeg** (`jfdctint.c`, "islow", Loeffler,
Ligtenberg and Moschytz), 8-bit samples, `CONST_BITS = 13`, `PASS1_BITS = 2`,
exactly as below. Rejected alternatives:

- *A float or higher-precision DCT*: not exact in hardware, and gives the
  golden model nothing to be exact against.
- *A shorter fast integer DCT (libjpeg "ifast")*: smaller multipliers, but it
  needs a scaled quantization table that changes the loaded-table contract
  (the chip would have to rescale host tables) and has visibly worse accuracy.
- *A different 13-bit-constant design of our own*: nothing is gained, and the
  independent libjpeg cross-check (spec §11) would be lost.

All arithmetic is two's-complement integer. `>>` is an arithmetic right
shift (floor). `DESCALE(x, n) = (x + (1 << (n-1))) >> n`.

### Constants (`FIX(x) = floor(x * 2^13 + 0.5)`)

| Name | Value | Name | Value |
|---|---|---|---|
| FIX_0_298631336 | 2446 | FIX_1_501321110 | 12299 |
| FIX_0_390180644 | 3196 | FIX_1_847759065 | 15137 |
| FIX_0_541196100 | 4433 | FIX_1_961570560 | 16069 |
| FIX_0_765366865 | 6270 | FIX_2_053119869 | 16819 |
| FIX_0_899976223 | 7373 | FIX_2_562915447 | 20995 |
| FIX_1_175875602 | 9633 | FIX_3_072711026 | 25172 |

### One-dimensional 8-point pass

Input d0..d7. Pass P is 1 (rows) or 2 (columns); `S = CONST_BITS - PASS1_BITS
= 11` in pass 1 and `S = CONST_BITS + PASS1_BITS = 15` in pass 2.

```
t0 = d0 + d7   t7 = d0 - d7        t1 = d1 + d6   t6 = d1 - d6
t2 = d2 + d5   t5 = d2 - d5        t3 = d3 + d4   t4 = d3 - d4

t10 = t0 + t3  t13 = t0 - t3       t11 = t1 + t2  t12 = t1 - t2

pass 1:  o0 = (t10 + t11) << 2     o4 = (t10 - t11) << 2
pass 2:  o0 = DESCALE(t10 + t11, 2)   o4 = DESCALE(t10 - t11, 2)

z1 = (t12 + t13) * 4433
o2 = DESCALE(z1 + t13 *  6270, S)
o6 = DESCALE(z1 + t12 * -15137, S)

z1 = t4 + t7   z2 = t5 + t6   z3 = t4 + t6   z4 = t5 + t7
z5 = (z3 + z4) * 9633
t4 *= 2446   t5 *= 16819   t6 *= 25172   t7 *= 12299
z1 *= -7373  z2 *= -20995  z3 *= -16069  z4 *= -3196
z3 += z5     z4 += z5

o7 = DESCALE(t4 + z1 + z3, S)     o5 = DESCALE(t5 + z2 + z4, S)
o3 = DESCALE(t6 + z2 + z3, S)     o1 = DESCALE(t7 + z1 + z4, S)
```

### Two-dimensional block

1. Level shift: `d = sample - 128`, giving -128..127.
2. Pass 1 on each of the 8 rows (d0..d7 are the row's columns 0..7); the
   result o_c is the coefficient of horizontal frequency c for that row.
3. Pass 2 on each of the 8 columns of the pass-1 result (d0..d7 are rows
   0..7); the result o_r is vertical frequency r.
4. The output array is row-major by (vertical, horizontal) frequency. It is
   **8 times the orthonormal DCT** (the scale is removed in the quantizer,
   `spec/codec.md` §5, by `D = 8 * Q`). No rounding happens between passes
   other than the DESCALE shown.

### Word lengths (all signed two's complement)

Bounds were found by running every sign pattern of the extreme inputs through
the datapath, which is exact for the linear nodes (a linear function over a
box peaks at a vertex). Measured on 2026-10-17 with a throwaway script, to be
re-derived by the golden-model issue's committed bound check.

| Quantity | Worst case seen | Width |
|---|---|---|
| Input after level shift | -128..127 | 8 |
| Pass 1 internal nodes (any `t`, `z`, product, sum before DESCALE) | 9,825,660 | **25** |
| Pass 1 output (stored in the transpose memory) | 4096 | **14** |
| Pass 2 internal nodes, with every pass-1 output taken as +-4096 | 315,654,144 | **30** |
| Pass 2 output | DC -8192..8128; AC below 8192 | **15** |

The pass-2 bound is conservative: it lets all eight pass-1 outputs reach 4096
at once, though only indices 0 and 4 can. A narrower datapath needs a proof
that is not given here; no width below the table is ratified.
Multiplications are by the constants above; the RTL may implement them as
shift-and-add so long as every node is bit-identical to the text.

## Worked examples (derived, then reproduced by the golden-model cross-check)

**One row, pass 1.** Samples 52, 55, 61, 66, 70, 61, 64, 73; after the level
shift d = -76, -73, -67, -62, -58, -67, -64, -55:

```
t0 = -131  t1 = -137  t2 = -134  t3 = -120
t7 =  -21  t6 =   -9  t5 =    0  t4 =   -4
t10 + t11 = -522  so  o0 = -522 << 2 = -2088
```

and the eight outputs are `-2088, -163, -64, -76, 80, -35, -8, 27`.

**A whole block.** Eight rows of samples (T.81-style example, a common test
block):

```
52 55 61 66 70 61 64 73
63 59 55 90 109 85 69 72
62 59 68 113 144 104 66 73
63 58 71 122 154 106 70 69
67 61 68 104 126 88 68 70
79 65 60 70 77 68 58 75
85 71 64 59 55 61 65 83
87 79 69 68 65 76 78 94
```

gives, after both passes, first two output rows
`-3323 -241 -489 218 449 -160 -19 4` and `36 -174 -486 82 105 -57 -68 39`.
The DC term is -3323 = 8 x -415.4, which is the textbook value -415.4 of this
block scaled by 8. Quantized with the Annex K luma table these become the first
two rows listed in `spec/codec.md` §5, and the full block entropy-codes to the
scan bytes in §6.

Flat blocks: all samples 255 gives DC 8128 and every AC 0; all samples 0 gives
DC -8192 (the minimum).

## Evidence and what is not yet evidenced

- Exploratory (2026-10-17, throwaway script, not committed): this arithmetic,
  with the quantizer and coder of `spec/codec.md`, reproduced libjpeg-turbo
  2.1.5's entropy-coded bytes on 9 of 9 greyscale and colour trials, and the
  block above reproduces the textbook coefficients. That supports the
  constants and the pass structure; it is not the committed bit-exact proof.
- Not evidenced: the width table is a bound from extremal inputs, not from a
  formal proof; the golden-model issue commits the script that regenerates it.
- The committed golden model (`verification/golden/jpeg_golden.py`) is the
  reference, not libjpeg. If the two ever differ the text above decides, and
  the difference is a finding to record.

## Consequences

- The quantizer, not the DCT, removes the factor 8; the chip stores no extra
  scale table.
- The DCT needs two 8-point engines or one used twice per block, and a
  transposition memory of 64 x 14 bits; that is decision 0004's
  standard-cell register file.
- Multiplier constants are 15 bits at most; no multiplier wider than
  17 x 15 bits is needed (pass 2 operands reach 17 bits after the first sum).
