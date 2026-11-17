# Decision record 0011: stage 1's retime latency pricing — `L` cycles of first-MCU latency per MCU, not `6L`

**Status**: Decided, 2026-11-16 (issue #160)
**Resolves**: #160 — 0010 §3's stage-1 bullet prices the inserted chroma-lane latency as `L beats × 6 blocks` of first-MCU latency per MCU; the correct price is `L`.
**Spec**: `spec/codec.md` §9, §10 (unchanged); amends `spec/decision-records/0010-retime-depth-allowance.md` §3 (the stage-1 bullet's pricing parenthetical only). No bound changes: `L ≤ 47`, stage 1's 768-cycle row, the 4439 first-MCU latency sum, and the 90.2% frame bound all stand as ratified.

## Question

Record 0010 §3 prices the stage-1 ceiling's cost as: "each beat of latency
adds ~6 cycles of first-MCU latency per MCU (L beats × 6 blocks)". Stage 3's
pricing in the same section carries a genuine `× 6` — quant's `k`-cycle
latency applies per block, and a 4:2:0 MCU has 6 blocks, so stage 3's row
moves `(72+k) × 6` (438 / 444 / 450 at `k` = 1 / 2 / 3). Is the same factor
correct for stage 1 — that is, does one beat of inserted chroma-lane latency
cost 6 cycles of first-MCU latency per MCU, or 1?

## Evidence

Three committed facts, each independently decisive:

1. **0007 §4's re-derived table distinguishes per-MCU rows from per-block
   rows.** Its row 1 is a bare **768** with no per-block arrow
   (`spec/decision-records/0007-pre-route-setup-shortfall.md:202`), while
   rows 2 and 3 carry per-block arrows — "172 per block → **1032**" and
   "73 per block → **438**" (`:203-204`). The `× 6` in those arrows is the 6
   blocks of a 4:2:0 MCU, applied where the stage genuinely runs per block.
2. **Row 1's 768 is the whole MCU, not one block.** 0007 gives its
   construction directly: "**768** (3 beats x 256 pixels at one 8-bit beat
   per cycle)" (`:266`). 256 pixels is the entire 16×16 macroblock, so the 6
   blocks are already inside the 768; multiplying the price again
   double-counts them.
3. **The RTL has no per-block chroma pass.** In `rtl/jc_downsample.v:84-131`
   the chroma lane is a single raster datapath indexed by `px`/`py` (4-bit,
   0–15 across the MCU) at the `pix_done` cadence, with
   `px == 4'd15 && py == 4'd15` as the macroblock end. The six blocks appear
   only as *output* word offsets — `cb_off = 7'd64 + …`, `cr_off = 7'd80 +
   …` — not as six passes over the pixels.

A feed-forward retime of that one lane therefore delays the MCU's *last*
chroma sample by `L` beats, and stage 1's contribution to the first-MCU
latency sum `768 + 1032 + 438 + 952 + 1249 = 4439` (`0007:214`) grows by
`L`, not `6L`.

**Impact of the error, and its direction.** At 0010 §3's ceiling `L ≤ 47`,
the stated pricing yields ≤ 282 cycles of first-MCU latency against the
correct ≤ 47 — an over-statement of ≤ 235 cycles on the ~1,503,866-cycle
frame bound (< 0.02%), inside the 90.2% figure's rounding. The wrong figure
**over**-states the cost, so it errs conservative: no bound in 0010 or 0007
is made to look safer than it is. Nonetheless it is wrong, and a published
price is exactly the kind of figure a later record cites as a bound — hence
this record rather than silence.

## Decision

1. **Stage 1's pricing is corrected to `L` cycles of first-MCU latency.**
   Each beat of inserted chroma-lane latency adds 1 cycle, so `L` beats add
   `L` cycles, because stage 1's row is one raster ingest of the whole
   16×16 MCU per MCU (3 beats × 256 pixels), not six per-block passes. The
   `× 6` factor is stage 3's, and stays correct there.
2. **No bound changes.** `L ≤ 47` is derived from the 48-beat
   `acc_cb`/`acc_cr` row-carry recurrence, not from this pricing, so the
   ceiling stands untouched. Stage 1's row staying 768 — "the added depth
   costs latency, not throughput" — is itself correct (0007 §4's row-1
   note), and only the parenthetical price alongside it was wrong. The
   4439 sum, the §4 band pricing, and the 90.2% frame figure all stand.
3. **0010 §3 is amended by pointer, not edited.** The erroneous sentence
   remains as written and an amendment pointer names this record and
   summarises the correction, per `spec/README.md`'s rule ("A change to a
   ratified row needs a new decision record, not an edit") — the same rule
   0010 followed when amending 0007 §4/§5.

## Rejected alternatives

- *Edit 0010 §3's sentence in place.* Forbidden by `spec/README.md`: a
  ratified row changes by new record, not by edit. 0010 itself applied this
  rule when correcting 0007, leaving the superseded clauses in place with
  pointers.
- *Fold the correction into #132's measured-retime record.* #132 is the
  issue that will actually insert the chroma-lane latency and may land its
  own record with the measured depth, but deferring would leave a wrong
  published price standing for as long as #132 takes. This correction rests
  on committed evidence alone and needs no measurement. If #132's record
  lands the same correction independently, the two records agree and both
  stand.
- *Retire the stage-1 ceiling or re-derive `L ≤ 47`.* The ceiling is
  correct: it bounds the inserted depth by the accumulator row-carry, not by
  this latency price, and the price sits alongside it only to make "beyond"
  decidable. Removing it would narrow the allowance without cause.

## Consequences

- **A reader of 0010 §3's stage-1 bullet follows the amendment pointer** to
  this record; the bullet's original text is not edited.
- **Any future record or budget that prices stage-1 latency uses 1 cycle
  per beat of inserted chroma-lane depth (`L` cycles for `L` beats)** —
  including #132's measured-retime record and any frame-bound derivation
  that consumes its result.
- **No RTL, netlist, golden-model, `flow/records/` or
  `verification/records/` file changes**: `rtl/jc_downsample.v` is cited as
  evidence only, and `flow/records/` is append-only — this record appends
  nothing.
- **Both §3 ceilings still sit far beyond any demanded depth** (`k` = 3–4
  expected), so the operative bound remains the measured STA; the
  correction changes a ceiling's published price, not the allowance.
