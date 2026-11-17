# Decision record 0009: pipelining the `jc_huff` symbol path (the q95 frame-rate remedy)

**Status**: Decided, 2026-11-15, issue #137
**Resolves**: #137 (the RTL remedy record 0008's option B deferred)
**Spec**: `spec/codec.md` §9 (unchanged); amends `spec/decision-records/0005-rtl-microarchitecture.md` §7 row 4 and its "Slowest stage" and "Frame bound" paragraphs; co-decided with `spec/decision-records/0007-pre-route-setup-shortfall.md` (§4's depth band sets the stage-2 rows this record prices against)

## Question

Record 0008 counted the q95 row of the §9 target (`noise_max_entropy_640x480`
at quality 95) at 1,740,070 cycles to `out_last` — 104.4% of the
1,666,667-cycle frame period — and identified the binder as `jc_huff`'s
four-state blocking FSM (`ST_IN` → `ST_ISSUE` → `ST_WAIT` → `ST_OUT`): every
symbol pays at least 4 cycles serialized behind the table-ROM round trip,
plus 1 cycle per in-run zero — a floor of 1448.2 cycles/MCU at q95. Option B
of record 0008, an RTL change to the binding stage, was deferred from that
record and filed as #137, to be co-decided with #127. Which symbol-path
microarchitecture closes the q95 gap without changing one output byte?

## Evidence

All figures are **simulated**, never measured (spec §9, CLAUDE.md).

- **The blocking FSM's cost reproduced exactly** (record
  `20261115T0046Z-frame-stages-61644ee`, record 0008): q95 `s7.transferred`
  = 425,695 symbols; the golden-model tally predicts a floor
  `4 x 425,695 + 35,105` = 1,737,885 cycles, 0.126% under the counted frame;
  `s6` (quant → huff) stalled 1,268,261 of 1,740,071 frame cycles (72.9%)
  while `s7`/`bp`/`out` stalled 9/0/0. Memory was exonerated: `m1_en`
  occupancy 342.8 cycles/MCU against §7's 708-cycle M1 row; `hf_m1`
  arbitration stalls 9 cycles per frame.
- **The memory-side rate this record must fit** (arithmetic from the counted
  record): at 1 symbol per 2 cycles the whole M1 traffic (411,326 accesses)
  needs 822,652 grant-slot cycles, 49.4% of the frame period — no port
  walls the design. `jc_bitpack` accepts one symbol per cycle when
  `cnt <= 13` and q95 averages 6.78 bits per symbol, so the byte-drain side
  does not bind on the §12 images. The A = 2 rule is the arbiter's
  (`jc_sram_arb`: `busy <= |g`, one grant per instance per two cycles), so
  the client presents a request whenever it holds a symbol and inherits the
  cadence without re-implementing it (record 0005 §5's one-outstanding-access
  contract is unchanged).
- **The re-count after this record's RTL** (record
  `20261115T1237Z-frame-stages-pipelined-83423424/`, same bench, same seed,
  same images): q95 needs **1,088,887 cycles** to `out_last` — **65.3% of
  the frame period, 45.9 frames/s simulated** — with `golden_match` true and
  360,997 output bytes, byte-for-byte the record 0008 count. The q50 rows
  are 982,462 / 982,464 cycles (58.9% each; the noise row improves from
  66.2%, which the blocking FSM also bound at q50). Output byte counts are
  unchanged on all three rows (18,616 / 126,543 / 360,997).
- **The binder moved to stage 2, as the corrected model predicts**: `s3`
  (mb_ctrl → dct) now carries the largest stall (882,354 cycles at q95)
  while `s7`/`bp`/`out` stay at 3,624/0/0. `jc_huff`'s own window is
  counted-derived at (2 x 425,695 + `hf_m1` 39,211 + `s7` 3,624) / 1200 =
  **745.2 cycles/MCU**, below the 768-cycle input row — stage 4 has stopped
  binding.
- **The unit rate is exactly 2.000 cycles/symbol**: `test_throughput`
  (added to `verification/rtl/test_entropy.py`) drives 48 fully dense
  blocks (3072 symbols) with unstalled memory and measures the span between
  the first and last beat `jc_huff` accepts: 6141 cycles over 3071 symbol
  intervals = 2.000 cycles/symbol, the A = 2 grant cadence, byte-exact
  against the spec §6 reference. In-run zeros are absorbed into the cycles
  the back end spends on the previous symbol (the same 1-cycle cost as
  before), so any beat mix sustains one beat per cycle at the front end.
- **The predicted `qa` contention materialized and is reported, not
  treated**: with `jc_huff` issuing one lookup per two cycles, the
  quantizer's Q-word holder (`qa_pend`, outranked by `jc_huff` in `u_arb1`)
  stalls 407,647 cycles at q95 (record 0008 counted 4,826). The frame
  correspondingly sits ~76,000 cycles above the pure stage-2 model row
  (1,012,868; see the combined figures below): the Q reads now wait behind
  `jc_huff`'s lookup rate and the wait bleeds into S5/S6 latency. §9 is met
  with 1.53x margin; the effect is a load shift onto stage 3's slack, not a
  regression of any ratified row. A future rebalancing of the quantizer's
  Q-path priority or prefetch is follow-up work and is **not** authorized by
  this record.

## Decision

**Pipeline the symbol path** (`rtl/jc_huff.v`, issue #137): split the module
into a *symbol-formation front end* and a *lookup/emit back end* joined by a
one-deep skid, keeping record 0005 §5's client port unchanged (one
outstanding access per client, `req` held until `gnt`, read data consumed in
the `rvalid` cycle).

- **Front end** (`FE_BEAT`/`FE_ZRL`/`FE_SYM`): accepts an S6 beat whenever
  it can form a symbol, computes the size category and additional bits,
  updates the DC predictors and run/position state, and pushes formed
  symbols `{kind, blk_end, last, comp, run, size, abits}` into the skid. A
  zero coefficient inside a run is absorbed in one cycle without a skid
  slot. ZRL expansion re-issues from the held coefficient without returning
  to beat acceptance; the EOB-at-position-63 rule is unchanged.
- **Back end** (`BE_IDLE`/`BE_REQ`/`BE_CAP`/`BE_HOLD`): pops one symbol,
  holds `m1_req`/`m2_req` asserted until the grant, forms `{len, bits}` at
  `rvalid`, and pushes it into a one-deep output skid so S7 back-pressure
  never stops issue (a capture that lands while the output skid is full
  waits in a holding register and stalls only then).
- **Steady state: one symbol per two cycles**, the A = 2 grant cadence; the
  front end sustains one beat per cycle on any content.

**Byte-exactness argument.** The change is pure scheduling. Every value the
S7 stream carries — the size category (`size_of`), the DC difference and its
sign remapping, the additional-bits field, the code word and its length from
the M1/M2 tables — is computed by the same arithmetic as the blocking FSM,
on the same inputs, in the same symbol order; only the cycle in which each
is computed moves. The DC-prediction state lives entirely in the front end,
updated at beat acceptance in stream order exactly as before; the predictor
reset moves from the final symbol's presentation to the final beat's
acceptance — both strictly after the frame's last predictor read and
strictly before the next frame's first DC beat, because the frame's final
beat is the last beat of the frame. `blk_end`/`last` are attached to the
symbol at formation from the same beat tag the FSM latched. Verified by the
full entropy suite (`test_entropy.py`, 11 tests including randomized memory
stalls to 0.8 and output stalls to 0.97 — byte-exact at any grant latency)
and by the re-count's `golden_match` on all three rows with unchanged byte
counts; the committed golden records (180 cases) are re-checked when the
golden suite is run locally — no CI job runs it (the re-count record's
README states this).

**Rejected alternatives** (unchanged from the issue's curation, restated for
the record):

- *Two lookups in flight.* The client port is one outstanding access
  (record 0005 §5); changing it touches every client and the arbiter, for
  throughput the A = 2 rule caps anyway.
- *Caching the Annex K tables in flops inside `jc_huff`.* Deletes the
  M1/M2 lookup instead of pipelining it, duplicating table state record 0004
  put in SRAM and breaking the host-loaded-table path (`jc_table_load`).
- *A deeper output FIFO alone.* `s7` stalled 9 cycles in the whole frame —
  there is nothing downstream to buffer against; the one-deep output skid
  covers the observed back-pressure (3,624 cycles at q95, absorbed).
- *A §9 quality-range note* (record 0008's option C). The operator-level
  relaxation of the ratified spec remains rejected and unauthorized; the RTL
  remedy closed the gap instead.

## The resulting §7 row 4, and the combined frame figure

**Row 4 re-derived** (`spec/decision-records/0005-rtl-microarchitecture.md`
§7, amended by this record): the Huffman symbol path costs **2 cycles per
symbol (the A = 2 grant cadence) x symbols**, plus arbitration and S7
back-pressure — content-dependent, like the FSM floor it replaces (the
in-run zeros are absorbed into cycles the back end already spends; the
`+ 1 per in-run zero` term belongs to the blocking FSM's floor this path
replaces). At the q95 row of the §12 image the counted-derived figure is
745.2 cycles/MCU (53.7% of the 1388.9 budget row), against the blocking
FSM's 1448.2 (record 0008) and the row's original M1/M2 access pricing of
952, which undercounted the stage at ~2.1 cycles per symbol.

**Combined frame figure, slowest-stage model.** Record 0005 §7 ratifies
that stage rows overlap and the frame is set by the slowest stage, not the
sum: `1200 x max(stage) + first-MCU latency + header`. With stage 4 at
745.2 the binder at worst-case content is **stage 2**:

| DCT depth (record 0007 §4 band) | Stage 2 row | Binder | Frame cycles | % of period | frames/s simulated |
|---|---|---|---|---|---|
| 8 (RTL at the re-count) | 840 | stage 2 | 1,012,661 derived; **1,088,887 counted** (qa term, above) | 60.8% derived / **65.3% counted** | 49.4 / **45.9** |
| 10 (0007 §4 decided) | 1032 | stage 2 | 1,243,259 | 74.6% | 40.2 |
| 12 (0007 §4 band edge) | 1224 | stage 2 | 1,473,851 | 88.4% | 33.9 |

**Provenance of the depth-8 row.** Its counted figures (1,088,887 / 65.3% /
45.9 frames/s simulated) were counted before the depth-12 `jc_dct1d`
retiming (record 0007 §4's band edge) merged into this branch, so at the
tree as merged the operative row is the depth-12 one (1,473,851, 88.4%); a counted
re-run on the merged tree is committed as
`verification/records/20261117T2156Z-frame-cycles-depth12-39c70b2/`
(issue #197): 1,383,369 cycles to `out_last` (83.0% of the period, 36.1
frames/s simulated, `golden_match` true, byte counts unchanged), consistent
with that row.

The depth-10 and depth-12 rows use `0007-pre-route-setup-shortfall.md` §4's
re-derived stage rows (1032 / 1224 cycles/MCU) with this record's per-depth
latency term (first-MCU latency = serial stage sum 768 + 1032/1224 + 438 +
745.2 + 1249, plus the 627-byte header; stage 3 = 438 is record 0007 §4's
re-derived row, which supersedes 0005 §7's 432 — the two table rows above
are computed on this term). They sit 207 cycles under 0007 §4's
published 1,243,466 at depth 10 (the pre-0009 row 4, 952, priced into the
latency term) and 15 cycles under its published 1,473,866 at depth 12 —
that published figure reuses the depth-10 latency term, which under-counts
the band edge by the 192 extra stage-2 cycles; this record's per-depth term
is the honest arithmetic. The difference is ≤ 0.017% and changes no
conclusion. §9 is met across the whole authorized depth band, with the
margin narrowing to 1.13x at the band edge — this record closes the gap but
leaves no room for a second regression on stage 2. Because stage 4 (745.2)
is below the 768 input row, `jc_huff` cannot become the binding stage again
at any content or quality, anywhere in record 0007 §4's authorized depth
band.

**On the counted cycles/symbol figures.** The issue's acceptance criteria
ask for `cycles_to_out_last` ÷ 425,695 and classify it against thresholds
(2.08 / 2.83 / 3.37 / 3.83) that are defined on the stage's own window. The
two are not the same number: the frame ratio has a mechanical floor of
921,600 / 425,695 = **2.165** — the input-bus row alone — for *any*
implementation, so it cannot reach ≤ 2.08. Counted: **2.558**
(1,088,887 / 425,695), i.e. the frame ratio of a design whose binder is
stage 2 with the `qa` contention term; the target outcome the issue's own
corrected model describes (frame 1,012,868, `jc_huff` below the input row)
reads 2.379 on the same ratio. The per-symbol thresholds are therefore
evaluated on `jc_huff`'s stage window: **2.000 simulated sustained** (unit
bench), 745.2 cycles/MCU counted-derived in the frame — **≤ 2.08: `jc_huff`
never binds again, the goal band**, confirmed by the binder's move to stage
2 in the re-count.

## Supersession

This record supersedes, in `0005-rtl-microarchitecture.md` §7: row 4's
original M1/M2 access pricing (952 cycles/MCU), and the "Slowest stage" and
"Frame bound" paragraphs that named stage 5 (1249) the worst-case binder.
Issue #136 (`loom:issue` + `loom:curated`, **unmerged at build time**,
2026-11-15, PR #149) corrects the same row in the same direction — to the
blocking FSM's counted floor of 1448 (record 0008) — and restates the same
paragraphs around it. #136's correction is **absorbed, not reverted**: its
1448 figure is the true cost of the *replaced* FSM, quoted above as the
baseline this record's remedy removes. Whichever of the two changes merges
second rebases onto the other: if #136 lands first, this record's row
replaces its text; if this record lands first, #136's row-4/paragraph
diffs conflict and its substance (the FSM floor, the stage-4 binder at q95,
the honest 104.6% frame bound for the pre-0009 RTL) is already carried in
this record's Evidence and baseline. The q95 shortfall both records document
is closed by this record's RTL; §9's ratified target row is unchanged.

## Consequences

- **`rtl/jc_huff.v`'s internals are re-owned by this record**; its ports,
  stream widths and the S6/S7 contracts of record 0005 §4 are unchanged
  (no re-port), so no interface freeze is touched.
- **The `qa` interaction is now a first-order effect** at q95-grade M1
  rates (407,647 stalls counted). Any future stage that adds M1 traffic on
  top of `jc_huff`'s one-access-per-two-cycles must re-derive §7's M1
  occupancy and the quantizer's slack together; this record's frame figures
  are valid for the current stage set only.
- **Verification**: `test_entropy.py` gains the sustained-rate test
  (`test_throughput`, 2.000 cycles/symbol asserted on the entropy stage's
  own port); `test_top_frame_cycles.py` is unchanged and its three rows are
  re-counted into `verification/records/20261115T1237Z-frame-stages-pipelined-83423424/`.
  The frame-rate figures remain simulated, never measured.
