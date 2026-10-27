# Decision record 0006: odd-size padding versus libjpeg-turbo

**Status**: Proposed, awaiting an operator ruling (issue #59). Nothing in the
golden model, the spec or the cross-check changes until it is ratified.
**Spec**: `spec/codec.md` §2 (Non-multiple sizes), §11, §12

## Question

The golden model and libjpeg-turbo write different entropy-coded segments for
any 4:2:0 image whose width or height is not a multiple of 16. Does the
ratified §2 rule stand, with the cross-check adapted, or does the golden model
(and so the RTL) follow libjpeg-turbo?

## Evidence

`verification/golden/diag_odd_size.py` (Pillow 10.2.0, libjpeg-turbo, q = 10,
50, 75, 95, 11 sizes). Golden against libjpeg on the true-size image differs at
every size that is not a multiple of 16 (including 104, 56, 60 and 50). Three
mechanisms, all of them libjpeg behaviour that §2 does not describe:

1. **Dummy luma blocks.** Luma blocks beyond ceil(w/8) x ceil(h/8) are not
   coded from replicated pixels: libjpeg writes DC equal to the previous
   block's DC and all-zero AC. This is the width failure at 100 and 104 and the
   height failure at 50 and 56. First differing block at 104x48, MCU (0,6),
   luma block 1: golden DC -59 with 4 non-zero AC, libjpeg DC -68 with none.
2. **Horizontal chroma edge.** The last full-resolution column is replicated to
   the chroma block grid before 2 x 2 averaging. Golden already does this.
3. **Vertical chroma edge.** An odd row is replicated to an even count, the
   2 x 2 average is taken, then the *chroma* plane is padded by replicating its
   last chroma row. Golden replicates full-resolution rows before averaging, so
   the last chroma row differs. This is the 64x60 failure (no dummy blocks
   there; chroma blocks 4 and 5 of MCU (3,2) differ).

A model of 1 to 3 (`libjpeg_model`) matches libjpeg byte for byte at all sizes
and qualities. Separately, golden on the true-size image equals libjpeg on the
same image **edge-replicated by the host to a whole MCU** at every size and
quality, which is exactly the §2 contract (the host pads, the chip codes whole
MCUs). Greyscale is unaffected (8 x 8 MCU, no chroma).

## Options

- **A. Keep §2. Cross-check odd sizes against libjpeg on the host-padded
  image** (recommended). Spec, golden and RTL unchanged; the chip stays unaware
  of padding. The cross-check feeds libjpeg the padded image and compares the
  scan; SOF0 dimensions are not part of the scan. Gives up: libjpeg on the true
  size image is not byte-identical.
- **B. Change the golden model and RTL to follow libjpeg-turbo.** Byte-equal to
  libjpeg on any size. Gives up: the chip must know the true size (dummy luma
  blocks, chroma-domain row padding), which contradicts §2's "unaware of
  padding", changes the block-ordered host interface of decision 0002 and adds
  RTL control for no throughput benefit.

## Decision

Pending. Whichever is ratified, golden/spec changes and the extra `SIZES`
entries are a follow-up (`Part of #59`), and the passing run is recorded under
`verification/records/`.
