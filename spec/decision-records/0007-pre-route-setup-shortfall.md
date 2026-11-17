# Decision record 0007: the pre-route setup shortfall response — pipelining the three wide arithmetic blocks

**Status**: Decided, 2026-11-14
**Resolves**: issue #127 (pre-route setup shortfall in `jc_dct`, `jc_downsample` and `jc_quant`)
**Spec**: `spec/codec.md` §9 (throughput), §10 (signoff clock, library, supply and corners); records 0003, 0005, 0008

## Question

The pre-route STA of the synthesized netlist (issue #114) found setup violated
by up to **31.07 ns** against the 20 ns signoff clock — `fmax` **19.58 MHz**
against the ratified 50 MHz — with three modules missing setup even at the
typical view. The response is an architecture question, not a local fix: act
now or wait for wire-aware post-route numbers; if act, which response —
slower clock, spec change, or datapath; and at what cycle cost, given that
#119's counted cycles already exceed every stage budget at quality 95.

## Evidence: the shortfall and what bounds it

Provenance: `flow/records/20261114T073850Z-62d88e1/`, run 2026-11-14 at repo
`62d88e1` (issue #114). Twelve `status: ok` per-module responses, all reading
the netlist with input content hash
`sha256:e32b0e8b820d07887a6b19d81b3beb63bffe334dabdcd66c04c8f7d227d8c3ee`,
constrained at `clock_period_ns: 20.0` with 2 ns input and output delay, over
the five `spec/codec.md` §10 views, `geometry_source: netlist_estimate`.
Sixty module/view points; **17 negative**. Worst setup slack over all points:
`jc_dct` at `ss_125C_3v00`, **−31.0688 ns** (`fmax_mhz: 19.5814`,
`setup_violation_count: 1253`, `total_negative_slack_ns: −16604.2`), path
`u_eng/_14559_/Q` → `u_eng/_14973_/D` — a **51.07 ns** cell-only path against
the 20 ns clock. Hold is met at every point
(`total_negative_hold_slack_ns = 0` in all sixty).

The three modules that miss at the typical view (cell-only worst setup slack,
ns):

| Module | `ss_125C_3v00` | `ss_n40C_3v00` | `tt_025C_3v30` | `ff_n40C_3v60` | `ff_125C_3v60` |
|---|---|---|---|---|---|
| `jc_dct` | −31.0688 | −14.6693 | −5.3047 | +5.5178 | −1.3806 |
| `jc_downsample` | −31.0417 | −15.0413 | −5.9176 | +4.4329 | −1.9641 |
| `jc_quant` | −30.1985 | −13.6722 | −4.7677 | +5.8608 | −1.0137 |

Each misses at four of the five views; `ff_n40C_3v60` is the only view where
they meet. Five further modules miss at `ss_125C_3v00` only, with gaps an
order of magnitude smaller: `jc_table_load` −4.4385, `jc_huff` −3.0153,
`jc_header_gen` −2.3547, `jc_qoi` −1.8477, `jc_bitpack` −1.5739. Cell count
does not predict the failure: `jc_zigzag` is the second-largest module (6197
cells against `jc_dct1d`'s 7808) and meets setup at all five views
(+3.1756 ns at `ss_125C_3v00`); combinational depth does.

Three bounds on these numbers, stated so the decision is not over-read:

- **Cell delays only.** The resolved library declares no `wire_load` group,
  so OpenSTA attached zero interconnect — not a small estimate, zero. Real
  post-route numbers will be worse by an unknown margin; these are the
  optimistic end.
- **Submodule-scoped.** Each module's ports carry a synthetic 2 ns I/O delay,
  so inter-module paths are not covered and the per-module slacks are neither
  an upper nor a lower bound on the stitched design.
- **Macro paths absent, not merely untimed.** `jpeg_codec_top` does not link
  without the `gf180_sram_256x32` LEF (#31), so `jc_sram_wrap` and everything
  reached through it has no row anywhere in the record.

Not a synthesis-setup artifact: `flow/synthesize.json` already constrains
synthesis to `clock_period_ns: 20.0` at `pdk.corner: ss_125C_3v00`, and
`flow/netlist/report.json` records `timing.delay_target_ps: 20000` against
`critical_path_ps: 48058.32` (`timing.source: abc_stime`, `sta: null`). ABC
was given the target and missed it 2.4x on its own estimate; OpenSTA's
measurement is 6% worse still.

## Assumption: interconnect fraction W

The STA record attaches zero interconnect, so every path above is cell delay
only. Call **W** the fraction of the cell-only critical-path delay that
routing adds on the same endpoint pair. No committed measurement bounds W:
the first wire-aware numbers are #34's (post-route five-view STA with SPEF),
which are blocked on #31 (the external `gf180_sram_256x32` LEF/GDS), so the
wait is unbounded.

This record budgets **W = 0.5**: routing adds half the cell delay. Requiring
post-route setup to close at the signoff view (path ≤ 20 ns at
`ss_125C_3v00`) then requires the cell-only path ≤ 20 / (1 + 0.5) =
**13.3 ns**, i.e. cell-only setup slack **≥ +6.7 ns** at `ss_125C_3v00`.
W = 0.5 is a planning value, not a measurement — the issue's own bound ("the
optimistic end") only says the true fraction is positive. It is flagged here
with an explicit re-derivation clause: when the first #34-class wire-aware
measurement exists for any path of this block, W is re-derived from it
(post-route path / cell-only path on the same endpoint pair), the target is
re-computed as 20 − 20/(1+W) in a new record, and follow-up issues that met
the old target are re-checked against the new one. Nothing else in this
record depends on W: the direction, the byte-exactness invariant and the
cycle cost stand at any W.

## Decision

### 1. Direction: reduce combinational depth by pipelining, bit-identical

Each of the three failing modules holds exactly one wide one-cycle arithmetic
block. The mechanism, per module, is **inferred from source, not traced** —
no path trace was run; a measured refutation of this table by the follow-up
issue's STA run is a complete, successful outcome, not a failure to deliver.

| Module | Block | Source | One-cycle work |
|---|---|---|---|
| `jc_dct` | `jc_dct1d` (`u_eng`) | `rtl/jc_dct.v:83`, `rtl/jc_dct1d.v:79-80`, `:151-158` | input flops → butterfly adder chain → step mux → two 17 x 15-bit multiplies → product flops; and product flops → 30-bit combine → variable `>>>` → `o_flat` flop, inside one cycle of the 8-cycle vector schedule |
| `jc_downsample` | `colour_convert` (`u_cc`) | `rtl/jc_downsample.v:65`, `rtl/colour_convert.v:23-31` | pixel flops → nine 8 x 16-bit constant multiplies in three 25-bit sums, plus `>>> 16`, all combinational (no `clk` port) |
| `jc_quant` | `jc_quant_core` | `rtl/jc_quant.v:61`, `rtl/jc_quant_core.v:28-29`, `:295` | `x` flop → 255-entry 20-bit reciprocal ROM mux → 11 x 20 multiply → clamp → `q` flop, all combinational (no `clk` port) |

The decided response: **insert registers into these combinational networks —
pipelining only, no arithmetic change — holding every computed value
bit-identical.** Record 0005 ratifies no per-module clocking property for
these blocks: §1 fixes only the global conventions (one `clk`, rising-edge
registers, no latches, and the naming rule that every module but the top is
prefixed `jc_`), and §2 is a hierarchy/ownership table whose
colour-conversion and quantizer rows are named `jc_color_convert` and
`jc_quant`. The RTL diverges from that table, and this record closes the
divergence: `rtl/colour_convert.v` is unprefixed against §1's naming rule
and appears in §2 under no name, while `rtl/jc_quant_core.v` is a further
split of the tabled `jc_quant` — a file §2 lets a stage issue add under its
own `jc_<stage>_` prefix. Registering either network — re-porting it as
sequential, or placing the equivalent registers in its parent `jc_downsample`
or `jc_quant` — is a change §2's closing rule ("may not rename or re-port a
module in this table without a new record") reserves to a new record; **this
record is that authorization**, for both modules as they exist in `rtl/`.
For `jc_dct1d` — named in §2 inside the `jc_dct` row — the registered
version of the 0005 §6 schedule is decided in §4 below.

### 2. Per-module depth target

Pre-route, cell-only, at the signoff view:

| Module | Cell-only path today | Required reduction | Target |
|---|---|---|---|
| `jc_dct1d` (in `jc_dct`) | 51.07 ns (−31.0688) | 3.83x | setup slack **≥ +6.7 ns** at `ss_125C_3v00` |
| `colour_convert` (paths parent-scoped in `jc_downsample`) | 51.04 ns (−31.0417) | 3.83x | " |
| `jc_quant_core` (paths parent-scoped in `jc_quant`) | 50.20 ns (−30.1985) | 3.76x | " |

and **≥ 0 ns at every one of the five §10 views** — this half is
assumption-free and mechanically checkable by re-running the same per-module
STA flow. The +6.7 ns figure is the W = 0.5 margin of the assumption above;
the 0 ns-at-all-views half stands even if W is re-derived, since signoff
setup is checked at all five views. The follow-up issue's verification loop
is: retime, re-run the per-module pre-route STA, append the record directory,
and iterate inside the cycle allowance of §4 until the target is met. If a
segment of the retimed path still misses at +6.7 ns, the answer is one more
register stage within the allowance — not a softened target.

### 3. What the retiming must not do

Pure retiming — moving a register boundary across combinational logic without
changing any arithmetic operation, operand value or rounding point — leaves
every computed value identical, so record 0003's bit-for-bit DCT arithmetic
and the committed golden model are unaffected **by construction**. What
changes is latency and the per-vector schedule (0005 §6 and §7), which §4
re-derives. Events that void the invariant and are **not authorized here**
(each requires record 0003's byte-exactness argument re-made in the
follow-up PR, explicitly, not absorbed): re-associating an adder tree (e.g.
re-grouping the butterfly sums), moving a rounding point (the `+ rnd` added
before a `>>>`), re-timing a shift across a rounding add, or any constant,
width or table change.

### 4. Cycle cost: schedule 8 → 10, authorized to 12

Record 0005 §7 budgets stage 2 (DCT) at 140 cycles/block = **840 per MCU**
against §9's **1388.9**, naming stage 5 (bit pack) at **1249** the binding
stage at worst-case content. Record 0008 has since corrected that premise
from the per-stage count: the binder at worst-case content is stage 4
(`jc_huff`), whose FSM floor is priced at **1448.2 cycles/MCU** at q95
(1,737,840 over 1200 MCUs, within 0.13% of the counted 1,740,070) against a
budgeted row of 952 that 0008 declares broken (its re-pricing is #136's,
targeting ~1448–1460). Throughput is set by the slowest stage, so the
binding constraint on the DCT engine's depth is the §9 budget itself:
**13.72 cycles/vector** (`(1388.9/6 − 12)/16`) before 30 frames/s is missed
outright. Against the counted `jc_huff` floor, stage 2 would need
`6 x (16n + 12) ≥ 1448.2`, i.e. **n ≥ 14.3 cycles/vector**
(`(1448.2/6 − 12)/16`), to become the binder — the depth margin to the
binder is wider than §7's rows suggested.

**Decided**: the `jc_dct1d` schedule moves from 8 to **10 cycles/vector**
(concrete shape: register the butterfly outputs once per vector; keep
mux → multiply → product register as the multiply cycle; register the
30-bit combine; the descale/variable shift moves behind its own register).
**Authorized band**: up to **12 cycles/vector** if a measured path needs one
more stage — at the cap stage 2 is 1224 cycles/MCU, still below the counted
`jc_huff` floor of 1448.2 (stage 2 would not bind until 14.3) and below the
§9 budget that 13.72 exhausts; beyond 12 requires a new record, because the
remaining margin to both bounds is what #136's corrected row 4 and #137's
`jc_huff` remedy must also spend. `jc_quant_core`'s pipeline gains one stage at
the ROM/multiply boundary, optionally two; throughput stays one coefficient
per cycle. `colour_convert`'s pipeline gains one stage; pixel acceptance
stays one pixel per 3 beats.

**Amended by record 0010** (`spec/decision-records/0010-retime-depth-allowance.md`):
the two register-count clauses above are superseded by a measurement-bounded
allowance (§4's counts cannot reach §2's target by the pigeonhole bound on
the committed STA record; the depth is the follow-up issue's measured
outcome, subject to named, priced latency ceilings).

Re-derived §7 rows under the decided depths (per 4:2:0 MCU, colour, at
50 MHz):

| Stage | 0005 §7 row | Re-derived | % of 1388.9 |
|---|---|---|---|
| 1 Ingest, convert, downsample | 768 | **768** — unchanged: the added stage costs latency, not throughput | 55.3 |
| 2 M0 read, DCT (both passes) | 840 | 16 vectors x 10 + 12 fill/drain = 172 per block → **1032** | 74.3 |
| 3 Zig-zag, quantize | 432 | 64 + 9 latency = 73 per block → **438** | 31.5 |
| 4 Huffman symbol path | 952 | **952** — untouched by this record's retiming; **broken budget** per record 0008 (counted `jc_huff` floor 1448.2 at q95; re-pricing is #136's) | 68.5 |
| 5 Bit pack, worst-case content | 1249 | **1249** — untouched | 89.9 |
| M0 / M1 / M2 ports | 384 / 708 / 252 | unchanged (A = 2 untouched) | — |

At the authorized 12 cycles/vector, stage 2 becomes 16 x 12 + 12 = 204 per
block → **1224** (88.1%) — still below the counted `jc_huff` floor of
1448.2 (record 0008), so stage 2 does not become the binder for any depth
in the band; overtaking it would take ≥ 14.3 cycles/vector. Frame bound at
the target: the first-MCU latency under the re-derived rows is
768 + 1032 + 438 + 952 + 1249 = **4439** (0005 §7's 4241 re-derived), so
the typical-content bound becomes 1200 x 1032 + 4439 + 627 = **1,243,466**
(74.6%; was 60.8% at 840) and the §7-row worst-case bound becomes
1200 x 1249 + 4439 + 627 = **1,503,866** (90.2%). That worst-case bound
still prices the binder as §7's row 5; under 0008 the counted
worst-case-content figure is the q95 row — 1,740,070 cycles, **104.4%** of
the period — and closing it is #137's, not settled by this record.

**Amended by record 0013**
(`spec/decision-records/0013-post-0009-frame-bound.md`): both 90.2%
statements here (§4's 1,503,866 above and §5's "at every depth in the band"
below) price the pre-0009 §7 row 5 (1249) as the binder with row 4 at 952;
under `0009-huff-symbol-path-pipelining.md` the binder at worst-case
content is stage 2, and merged `0005-rtl-microarchitecture.md` §7's
per-depth rows give 60.8% (depth 8) – 88.4% (depth 12). The retiming
decision and the §2 target stand.

### 5. What this record settles — and what it does not

The counted cycles (record
`verification/records/20261114T0551Z-frame-cycles-62d88e1/`, on `main` since
PR #120 merged 2026-11-14) bound what the retiming may add. The increment is
at most +192 cycles/MCU (stage 2, 840 → 1032) plus +6 (quant latency) =
**+198**, landing fully only if the DCT or quant stage binds the counted
run. Record 0008's per-stage count answers that condition for q95: the
binder there is `jc_huff` (`s6` stalled 1,268,261 of 1,740,071 frame
cycles; `s7` stalled 9 and `bp`/`out` stalled 0), so the +198 is absorbed
by pipeline overlap at q95 and the q95 column below is the pessimistic end,
not the expected result. **Amended by record 0010**
(`spec/decision-records/0010-retime-depth-allowance.md`): the +198 prices
the **decided** depths (dct 10, quant 1); the corner of §4's band as
ratified is **+396** (dct 12, quant 2), and the additive q95 column is
classified there as a **sensitivity** on the counted q95 frame — 0005 §7
ratifies max-stage throughput, under which the frame bound is 90.2% at
every depth in the band. Against the counted figures:

| Row (counted) | Today | Worst case after retiming | §9 target row (30 frames/s) |
|---|---|---|---|
| `scene_fbm` q50 — 818.73 cyc/MCU | 58.9% | ≤ 73.2% (1,220,071 cycles) | met either way |
| `noise_max_entropy` q50 — 919.31 | 66.2% | ≤ 80.4% (1,340,767) | met either way |
| `noise_max_entropy` q95 — 1450.06 | 104.4% | 104.4% – **118.7%** (1,740,070 – 1,977,670) | **not met today; not settled here** |

**This record settles the clock-period response only.** It does **not**
settle the q95 cycle gap: record 0008 — resolving #119 from the per-stage
count committed in this tree
(`verification/records/20261115T0046Z-frame-stages-61644ee/`) — identified
the q95 binder as `jc_huff` (boundary `s6` stalled 1,268,261 of the
1,740,071 frame cycles; `s7` stalled 9 and `bp`/`out` stalled 0), priced
its FSM floor at 1448.2 cycles/MCU, and declared §7's row 4 a broken
budget. The remedy is filed as **#137** (removing `jc_huff`'s per-symbol
cycle floor), and #137 and this record are explicitly co-decided: retiming
`jc_huff` spends the cycle budget that this record's chosen depths (§4)
define, so this record supplies the depth side of #137's decision and #137's
counted cycle cost (the 1448.2 floor above, ~1448–1460 after #136's
re-pricing) is the figure both records must carry.

## Rejected alternatives

- *Lower the signoff clock to 25 MHz.* §9 pairs the 25 MHz column with the
  **fallback** row (320 x 240 grey); for the target row it allows
  25e6 / 36,000 = **694.4 cycles/MCU**, while the pixel input bus alone needs
  **768** (3 beats x 256 pixels at one 8-bit beat per cycle) = **110.6%**.
  640 x 480 at 30 frames/s in colour is infeasible at 25 MHz whatever the
  datapath does. `CLAUDE.md` independently forbids relaxing the ratified spec
  to make results pass.
- *Hold the decision until post-route numbers (#34).* The evidence is
  cell-delay-only, so wire-aware numbers are strictly worse: they can refine
  how much margin to design for, not change the sign of the shortfall. The
  wait is unbounded: #34 is blocked on #31, which waits on the external
  macro LEF/GDS. Waiting would carry a 2.6x gap into the floorplan.
- *Re-run synthesis harder.* Synthesis was already constrained at exactly
  this corner and clock (20 ns at `ss_125C_3v00`), and ABC's own estimate
  missed the target 2.4x. The depth is in the RTL's one-cycle arithmetic, not
  in the tool run.
- *Declare the engine's paths multicycle.* The 51 ns path executes in one
  clock cycle: the multipliers run every cycle of steps 1 to 6 and the
  combine in step 7 of the existing schedule. A multicycle exception would
  hide a real violation; §10 signoff STA is single-cycle.
- *Accept the shortfall and re-derive the frame rate from `fmax` 19.58 MHz.*
  That is ~39% of the 50 MHz target clock — below even the 25 MHz fallback
  row — and retiring the target row is a spec relaxation, forbidden.
- *A second DCT engine or more multipliers for throughput.* Record 0005 §7
  rejected this because 840 cycles/MCU was 60.5% of budget; that rejection
  stands and is not reopened. Multipliers may be re-deployed as a **depth**
  resource (shortening the multiply chain's logic per cycle) only within the
  ≤ 12 cycles/vector band of §4.

## Consequences

- **Three follow-on RTL issues**, one per module (`jc_dct1d`,
  `colour_convert`, `jc_quant_core`), are filed at `loom:triage` by #127.
  Each names its slack target (§2) and cycle allowance (§4), and each
  verifies by re-running the per-module pre-route STA (the flow of
  `flow/records/20261114T073850Z-62d88e1/`) and appending a new record
  directory — `flow/records/` stays append-only; nothing existing is edited
  or re-run.
- **0005 §6 and §7 are superseded for these modules**: the "one vector per
  8 cycles" sentence and the stage-2 and stage-3 rows are replaced by §4
  above. Record 0005 itself is not edited; a reader of 0005 follows its own
  rule and finds the new schedule here. §7's row 4 is separately corrected
  by record 0008 (the binder at worst-case content is `jc_huff`; counted
  floor 1448.2 cycles/MCU at q95) via #136, and the q95 gap's RTL remedy is
  #137, co-decided with this record's depths (§4) — this record re-prices
  neither row 4 nor the q95 closure.
- **W is provisional.** The +6.7 ns target inherits the W = 0.5 assumption
  with its re-derivation clause; the first wire-aware measurement re-derives
  it. A follow-up issue that met +6.7 ns is re-checked, not re-opened,
  unless the re-derived W demands more.
- **The five ss-only misses stay out of this record's direction.** Their
  gaps (1.57 to 4.44 ns at `ss_125C_3v00`, zero at the other views) are an
  order of magnitude smaller than the three addressed here; #34's wire-aware
  numbers decide whether they need the same treatment.
- **No ratified spec text changes.** `spec/codec.md` is untouched; §14's
  "whether 50 / 25 / 100 MHz *close*" stays deferred to #4 items 5, 7 and 8.
  This record chooses the response to a pre-route finding; it does not
  declare any clock closed.
- **Frame-rate figures remain claims from counted cycles** (spec §9):
  nothing in this record is measured; the percentages above are derived from
  budgets and counted simulation figures, never silicon.
- **Verification**: each follow-up issue states which re-derived row of §4
  its testbench checks; byte-exactness is asserted against the golden model
  by the existing suite on every retimed module, and any change of the kind
  §3 lists is called out with record 0003's argument re-made.
