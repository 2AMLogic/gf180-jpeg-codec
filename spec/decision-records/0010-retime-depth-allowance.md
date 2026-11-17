# Decision record 0010: the retime depth allowance for `colour_convert` and `jc_quant_core` — bounded by measurement, not by a register count

**Status**: Decided, 2026-11-15 (issue #144)
**Resolves**: #144 — record 0007 §4's authorized depth cannot reach §2's target for two of the three retimed modules
**Spec**: `spec/codec.md` §9, §10 (unchanged); amends `spec/decision-records/0007-pre-route-setup-shortfall.md` §4 (the authorized depth for `colour_convert` and `jc_quant_core`) and §5 (band pricing and the q95 column's classification). §2's target carries through unchanged.

Filed as 0010, not 0009: the 0009 slot was claimed in flight by #142's `0009-klt-pin-and-attest-binding.md` (merged via #147) after this issue's curation verified 0009 as the next free number against `origin/main` @ `eea3b13`; the highest committed number was re-checked at PR time.

## Question

Record 0007 §2 sets the per-module depth target — cell-only setup slack
**≥ +6.7 ns** at `ss_125C_3v00` and **≥ 0 ns at all five §10 views** — and
tells the follow-up issues to iterate "one more register stage **within the
allowance** — not a softened target". §4 then publishes the allowance: an
authorized cycle band for `jc_dct1d` (8 → 10 cycles/vector, up to 12,
"beyond 12 requires a new record"), but for the other two modules only a
register count — one stage for `colour_convert`, "one … optionally two" for
`jc_quant_core`. From the committed STA record, the pigeonhole bound shows
those counts cannot reach the target: which allowance makes §2 executable
for all three modules without softening the target and without pre-committing
a depth that only a measurement can decide?

## Evidence

Provenance: `flow/records/20261114T073850Z-62d88e1/` — the STA record 0007
cites in its Evidence section, re-read for this issue. `clock_skew_ns` is `0` at
every one of the five views of all three modules, `clock_uncertainty` is
`{"applied": false}`, `clock_mode` is `ideal`, period 20.0 ns — so for each
worst path `path = 20 − slack` exactly (as `fmax_mhz` is derived the same
way, this quantity is the *required cycle time including the endpoint flop's
setup*, not a pure combinational delay). Worst setup path at the signoff
view: `jc_downsample` 51.0418 ns (`slack_ns` −31.04175), `jc_quant`
50.1985 ns (−30.19849), `jc_dct` 51.0688 ns (−31.06883).

`k` inserted registers split a combinational path into `k+1` segments, so
the longest segment is at least `path/(k+1)` — and each added flop's setup +
clock-to-Q makes the split strictly worse, so the table below is a **lower
bound** on the demand, not a prediction. Slack = `20 − path/(k+1)`:

| Module | cell-only path | `k`=1 | `k`=2 | `k`=3 |
|---|---|---|---|---|
| `colour_convert` (`jc_downsample`) | 51.0418 ns | −5.52 ns | +2.99 ns | +7.24 ns |
| `jc_quant_core` (`jc_quant`) | 50.1985 ns | −5.10 ns | +3.27 ns | +7.45 ns |
| `jc_dct1d` (`jc_dct`) | 51.0688 ns | −5.53 ns | +2.98 ns | +7.23 ns |

Re-derived: the minimum depth is **`k` = 2 for ≥ 0 ns** and **`k` = 3 for
≥ +6.7 ns** — for all three modules. Against §4 as ratified (`k` = 1 for
`colour_convert`, `k` ≤ 2 for `jc_quant_core`):

- `colour_convert` at its authorized one stage reaches −5.52 ns — it misses
  even the assumption-free half of §2 (≥ 0 ns at all five views), not merely
  the W = 0.5 margin half.
- `jc_quant_core` at "optionally two" reaches +3.27 ns — ≥ 0, short of +6.7.
- `jc_dct1d` is fine: its band (≤ 12 cycles/vector) leaves room for the ~3
  register boundaries the table wants — the clause the other two rows lack.

§2's escape hatch — "one more register stage **within the allowance**" — is
therefore not executable for those two modules as ratified: the allowance is
what runs out. This is arithmetic on the committed STA record alone; no new
measurement is needed to establish it (the record below decides the *form*
of the allowance, not the depth).

Three further facts bound what the amended allowance may say:

- **The `colour_convert` span is lane- and entry-symmetric, wider than one
  net.** At four of the five views the worst path is not the
  `ss_125C_3v00` Cb-lane path the table above prices but a near-tied sibling:
  the **Cr** lane launched from the `pix_data` **port** (`pix_data[7]` →
  `crw[6]` at `ss_n40C_3v00` −15.0413, `tt_025C_3v30` −5.9176,
  `ff_125C_3v60` −1.9641; `ff_n40C_3v60` +4.4329 meets), against
  `g_q[4]` → `cbw[6]` (−31.04175) at the signoff view. Both lanes are the
  same chroma datapath — `rtl/jc_downsample.v:86` declares `cbw, crw`
  together — and the two startpoints are the pixel registers (`:42`) and the
  input port (`:31`, `input_delay_ns` 2.0). Which member is worst flips with
  corner derating, but the depth is set by the `ss_125C_3v00` member
  (51.0418 ns; every other member's demand there is smaller, since none of
  them is the reported worst). `colour_convert` is combinational with no
  `clk` port (`rtl/colour_convert.v:6-14`), so no depth placed inside it
  alone can cut the tail: the registers land in `jc_downsample`, which
  0007 §1 already authorizes by scoping the paths to the parent.
- **The `jc_quant_core` span is `jc_quant`'s datapath through the core.**
  The core is instantiated combinationally inside its parent
  (`rtl/jc_quant.v:61`: `jc_quant_core core (.x(s5_data), .qv(qv),
  .is_ac(cnt != 6'd0), .q(qo));`) and the exhaustive bench
  `verification/rtl/tb_quantizer_exhaustive.v` instantiates the core
  directly with **no clock** (`jc_quant_core dut (.x(x), .qv(qv),
  .is_ac(is_ac), .q(q));`).
  Registers placed inside the core would break that bench; the retime
  splits the core's combinational function and registers it in `jc_quant`
  around the core (#133's finding).
- **The depth is bounded by control bookkeeping, not by a register count.**
  In `rtl/jc_downsample.v:84-131`, `acc_cb/acc_cr[0:7]` is written on even
  rows (`c_store`) and read on odd rows (`c_out`) at the same
  `cx = px[3:1]` — a recurrence distance of one pixel row (16 pixels = 48
  beats) — and `pcb/pcr <= ccb/ccr` recurs at the pixel cadence. Both are
  far longer than any depth the STA table demands, so a feed-forward retime
  preserves one pixel per 3 beats at any such depth **provided**
  `cx`/`px`/`py`/`c_store`/`c_out`/`c_emit`/`cb_off` shift by exactly the
  inserted latency. Likewise `jc_quant`'s scheduler (`cnt`, `blk_comp`, the
  tag/valid plumbing and the `cur_word`/`nxt_word` prefetch) shifts by the
  inserted latency while one coefficient per cycle is preserved. This is
  what makes a measurement-bounded allowance sound rather than open-ended.

### Pricing the band (both axes)

The stage-3 row is `64 + (8+k) = 72+k` per block (0005 §7's "64
coefficients at 1 per cycle + 8 latency") → `(72+k) × 6` per MCU, and §5's
increment is `(stage-2 row − 840) + 6k`:

| dct cycles/vector | quant `k` | stage 2 | stage 3 | §5 increment | additive q95 |
|---|---|---|---|---|---|
| 10 | 1 | 1032 | 438 (31.5%) | **+198** | 1,977,670 (**118.7%**) |
| 10 | 2 | 1032 | 444 (32.0%) | +204 | 1,984,870 (119.1%) |
| 10 | 3 | 1032 | 450 (32.4%) | +210 | 1,992,070 (119.5%) |
| 12 | 1 | 1224 | 438 (31.5%) | +390 | 2,208,070 (132.5%) |
| 12 | 2 | 1224 | 444 (32.0%) | **+396** | 2,215,270 (**132.9%**) |
| 12 | 3 | 1224 | 450 (32.4%) | +402 | 2,222,470 (133.3%) |

(additive q95 = counted 1,740,070 + 1200 × increment — the additive
construction 0007 §5 uses, whose serial sum 0005 §7 reports only as the
bound on first-MCU latency.) §5's published "at most **+198**" prices the **decided**
depths (dct 10, quant 1). The corner of the band §4 authorizes today is
dct 12 × quant 2 → increment **+396**, additive q95 **2,215,270
(132.9%)** — §5 does not price it.

Under record 0005 §7's ratified frame model the picture is different:
"**Throughput of the pipeline is therefore set by its slowest stage, not by
the sum of the stages**", and the binder at worst-case content is row 5
(1249) across the whole band — no stage-2 or stage-3 row in the table above
reaches it. The frame bound is therefore `1200 × 1249 + first-MCU latency +
627`, first-MCU latency 4439 … 4643 over the band, i.e.
**1,503,866 – 1,504,070 cycles = 90.2% at every depth in the band**
(this model reproduces 0005 §7's published 1,012,868 / 1,503,668 and 0007
§4's re-derived 1,243,466 / 1,503,866 exactly). The additive column is a
sensitivity on the counted q95 frame, not a throughput bound — 0007 §5
already labels it "the pessimistic end, not the expected result"; this
record says so formally and re-prices it to the band corner.

**Amended by record 0013**
(`spec/decision-records/0013-post-0009-frame-bound.md`): the "90.2% at
every depth in the band" here and in §4 below price the pre-0009 §7 row 5
(1249) as the binder with row 4 at 952; under
`0009-huff-symbol-path-pipelining.md` the binder at worst-case content is
stage 2 (96d + 72 cycles/MCU), and merged `0005-rtl-microarchitecture.md`
§7's per-depth rows give 60.8% (depth 8) – 88.4% (depth 12). The
measured-depth allowance and §4's classification of the additive column
stand.

## Decision

### 1. Authorized depth: measurement-bounded, not a register count

0007 §4's register-count clauses for the two modules are superseded:

- `colour_convert`'s pipeline gains as many stages as the **measured**
  per-module STA (the flow of
  `flow/records/20261114T073850Z-62d88e1/`) requires to meet §2;
- `jc_quant_core`'s pipeline likewise, throughput staying one coefficient
  per cycle.

in each case subject to (a) the throughput invariant (pixel acceptance one
pixel per 3 beats; one coefficient per cycle — both preserved at any depth
by a feed-forward retime), (b) the control-shift constraint of the
Evidence section (every schedule/control register shifts by exactly the
inserted latency; the accumulation pairing and the row-carry read schedule
are not restructured), and (c) the priced ceiling of §3 below.

**No depth figure is published as the decided depth.** The depth is
#132 / #133's measured outcome, exactly as §4 already leaves `jc_dct1d`'s
10-vs-12 to measurement inside its band. The Evidence section's table is a
pigeonhole lower bound (expected demand `k` = 3–4); ABC failed its own 20 ns
target 2.4x (`flow/netlist/report.json` `critical_path_ps` 48058.32), so
re-synthesis of a registered netlist against achievable per-segment targets
may shift the actual boundary. A clause that merely raised "optionally two"
to "optionally three" would reproduce the defect one step later — the count
was the defect.

### 2. The retime span, named per module, lane- and entry-symmetric

- **`colour_convert`**: `jc_downsample`'s chroma datapath — from the pixel
  entry (both the `pix_data` **port** and the `r_q`/`g_q` pixel registers)
  through `u_cc`'s `cb_sum`/`cr_sum` network and its `>>> 16`, `hs_cb`/
  `hs_cr`, `tot_cb`/`tot_cr` (including the `acc_cb`/`acc_cr[cx]` mux and
  the bias), `o_cb`/`o_cr`, to `cbw`/`crw` — **both lanes** (Cb and Cr),
  **both entry classes**. `colour_convert` is combinational with no `clk`
  port, so the inserted registers land in `jc_downsample` (authorized by
  0007 §1's parent-scoping). A depth placed inside `colour_convert` alone
  does not cut any tail path in the table above.
- **`jc_quant_core`**: `jc_quant`'s datapath through the core (`s5_data`/
  `qv` → reciprocal ROM mux → multiply → clamp → `s6_data`). The registers
  go in `jc_quant` around the core; registers **inside** `jc_quant_core`
  break `tb_quantizer_exhaustive`'s clockless instantiation and are not
  authorized.

### 3. The priced latency ceiling — beyond it, a new record

The allowance is finite, with the ceiling named and priced so that
"beyond" is decidable, parallel to `jc_dct1d`'s "beyond 12":

- **Stage 3 (`jc_quant`)**: the row `(72+k) × 6` must stay below the counted
  `jc_huff` floor of **1448.2 cycles/MCU** (record 0008) — formally
  **`k` ≤ 169**; beyond it stage 3 would overtake the binder and spend the
  margin #136's corrected row 4 and #137's `jc_huff` remedy must also
  spend. Priced: each stage adds +6 cycles/MCU to stage 3's row and to
  first-MCU latency (row 438 / 444 / 450 at k = 1 / 2 / 3 above).
- **Stage 1 (chroma lane)**: the inserted latency must stay **below the
  48-beat accumulator row-carry** (`acc_cb`/`acc_cr` written on even rows
  and read on odd rows at the same `cx`; 16 pixels × 3 beats) — formally
  **L ≤ 47 beats**; at or beyond it the odd-row read could race the next
  row's write and the unchanged-schedule accumulator contract is void —
  that restructuring requires a new record. Priced: each beat of latency
  adds ~6 cycles of first-MCU latency per MCU (L beats × 6 blocks); stage
  1's row stays 768 — the added depth costs latency, not throughput (0007
  §4's row-1 note).

  **Amended by record 0011**
  (`spec/decision-records/0011-stage1-retime-latency-pricing.md`): the
  stage-1 price above is corrected to **`L` cycles** of first-MCU latency
  per MCU, not `L × 6` — stage 1's 768-cycle row is one raster ingest of
  the whole 16×16 MCU (3 beats × 256 pixels, 0007 §4's row 1), not six
  per-block passes. The `L ≤ 47` ceiling and every other bound in this
  record stand; the old figure over-stated the cost (conservative
  direction).

Both ceilings sit far beyond any depth the Evidence table demands
(`k` = 3–4 expected), so the **operative bound is the measured STA**; the
ceilings exist to bound the allowance, not to predict the depth.

### 4. §5's q95 column: classified, not silently re-priced

Record 0005 §7 ratifies the max-stage model — "set by its slowest stage,
not by the sum of the stages" — and reports the serial sum only as the
bound on first-MCU latency. Under it the frame bound is **90.2% at every
depth in the band** (row 5's 1249 dominates throughout). §5's additive q95
column is therefore **a sensitivity on the counted q95 frame**, not a
throughput bound. This record **re-prices it to the band corner rather than
retiring it**: the additive column stays useful as the no-overlap
sensitivity, but it is now published at the corner §4 authorizes —
increment **+396**, additive q95 **2,215,270 = 132.9%** (dct 12 × quant 2)
— and labelled as what the frame would cost only if every added cycle
serialized, which the ratified model says it does not. §5's "at most +198"
stands as the **decided-depth** increment; the decided point's published
row (118.7%) is not edited.

### 5. §2 is untouched

The target carries through unchanged: **≥ +6.7 ns** at `ss_125C_3v00` and
**≥ 0 ns at all five §10 views**, with the W = 0.5 re-derivation clause
intact. This record widens the allowance; it does not touch the target, the
W assumption, or any ratified `spec/codec.md` text.

## Rejected alternatives

- *Raise "optionally two" to "optionally three" (a bigger count).* Same
  defect one step later: a count cannot reach a measured target — the next
  synthesis result could need `k` = 4, and the count would run out again.
- *Publish `k` = 3 now as the decided depth.* Pre-commits a measured
  outcome from a lower-bound argument — the same class of inference 0007 §1
  is careful to avoid ("a measured refutation of its inferred mechanism
  table is a complete, successful outcome"). The table is a bound, not a
  prediction; re-synthesis against per-segment targets may shorten
  segments.
- *Wait for #132 / #133 to amend 0007 with their measured STA.* Deadlocks
  both: a Builder on either hits §2's escape hatch and finds the ratified
  allowance arithmetically exhausted, and CLAUDE.md forbids relaxing the
  ratified spec to make results pass. This record decides the form of the
  allowance, which the committed STA record establishes by pigeonhole alone;
  neither issue is preempted — the depth remains theirs.
- *Soften §2's target to what `k` = 1/2 reaches.* Forbidden: issue #144
  requires §2 carried unchanged, and CLAUDE.md forbids relaxing the
  ratified spec to make results pass;
  record 0006 is the precedent that a §9-class relaxation needs an operator
  ruling, which the arithmetic here does not warrant.
- *Amend 0007 §4's clauses in place.* `spec/README.md` states the rule:
  a change to a ratified row needs a new decision record, not an edit. The
  pointers added to 0007 §4 and §5 name this record instead.

## Consequences

- **#132 and #133 are executable against §4 as amended**: their
  verification loop (retime → per-module STA → iterate) now has an
  allowance that cannot run out below §2's target; each appends the
  measured depth in its own record, and neither may publish this record's
  lower-bound table as its result.
- **0007 §4's count clauses for the two modules and §5's increment
  sentence are superseded for the band.** 0007 is not edited beyond the
  two amendment pointers required by `spec/README.md`'s rule; a reader of
  0007 follows the pointers.
- **`jc_dct1d` is untouched** (#131 absorbed): its authorized band already
  reaches its target; the band table above prices its stage-2 row at depth
  12 (1224 per MCU) and the +390 / +396 / +402 increments that follow.
  Nothing else about it changes here.
- **Row 4's re-pricing stays #136's and the q95 gap's closure stays
  #137's.** This record classifies §5's additive column and prices the
  band; it does not re-derive §7's row 4 against the counted floor and it
  does not close the q95 gap.
- **No RTL, netlist, golden-model, `flow/records/` or
  `verification/records/` file changes**: `flow/records/` is append-only
  and this record appends nothing; the committed STA record of 2026-11-14
  is the evidence.
- **Frame-rate figures remain claims from counted cycles** (spec §9):
  nothing here is measured; the percentages are derived from budgets and
  counted simulation figures, never silicon.
