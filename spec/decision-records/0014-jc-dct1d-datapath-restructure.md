# Decision record 0014: the `jc_dct1d` datapath restructure, measured — a CSD carry-save constant-multiply and sliced combine at 13 cycles/vector, closing §2's ≥ 0 ns half at every view

**Status**: Proposed, 2026-11-18 (issue #169). Ratification (two reviews, then the operator) is out of the filing issue's scope; per the operator ruling this record authorizes a bit-exact restructure, and the restructured RTL (`rtl/jc_dct1d.v` at this PR's head, sha256 `532857f192abc4f55a50c3b4f1f68d4916fa6be2eaa14df1402953e49ed24ee2`), its regenerated netlist (`flow/netlist/jpeg_codec_top_synth.v` sha256 `61cdd7a3db699a3e8331c47eea825ba6b57f8adc1f5eb7746f52a5e03b01e2dd`) and the re-priced budget line in `verification/rtl/test_dct.py` land only together with this record's ratification — until then they stay on the filing branch.
**Resolves**: #169 — record 0007 §2's timing target for `jc_dct1d` is unreachable by pipelining inside §4's authorized band (PR #164's measured evidence); the operator ruled option `a` on 2026-11-17 (attended `/fleet:decide` round 20261116-r15, q117): authorize a bit-exact restructure of the constant-multiply and combine datapath, depth bounded by measurement under §9's 13 cycles/vector ceiling.
**Spec**: `spec/codec.md` §9, §10 unchanged; amends `spec/decision-records/0007-pre-route-setup-shortfall.md` §1 (the pipelining-only clause, for `jc_dct1d` only) and §4 (the ≤ 12 cycles/vector band, superseded by this record's measured 13); §2's target carries through unchanged, both halves.

Filed as 0014 — the next free number at write time (0012 and 0013 are committed on `main` as of `cb51d92`, 2026-11-18; re-checked immediately before writing).

## Question

PR #164 exhausted record 0007 §4's band: all three in-band configurations measured −14.2442 to −15.4648 ns at `ss_125C_3v00`, each exposing a ~34–35 ns structural segment against the 20 ns budget. The operator authorized a bit-exact restructure of the constant-multiply and combine datapath with depth set by measurement under §9's 13 cycles/vector ceiling. What restructure closes §2's assumption-free half (≥ 0 ns setup slack at all five §10 views), at what cycle depth, and what does the measurement say about the ≥ +6.7 ns W = 0.5 half?

## Decision

### 1. The restructure, and what it gives up

For `jc_dct1d` only, record 0007 §1's "pipelining only, no arithmetic change" is **given up**, per the operator ruling. What replaces it is a register-boundary obligation stronger than the pipelining clause's "same operations": **every register boundary holds an exact partial of a value the 0007 §4 schedule computed exactly**, so every registered value is bit-identical and no proof over the intermediate combinational net is needed:

- **Twelve dedicated constant multipliers** replace the two operand-muxed time-shared multipliers. Each 17 × 15-bit constant multiply becomes a CSD shift-add tree: a positive digit contributes `op <<< k`, a negative digit contributes `~op <<< k` with the `+1 << k` folded as one constant term; the 3:2 carry-save layers are exact identities (`s + carry ≡ a + b + c` per bit position), so each tree's registered `(S, C)` pair satisfies `S + C = op × const` (mod 2^30). There is **no operand mux anywhere on the multiply path** — each tree reads its own operand register through fixed wires — which removes the 34.244 ns mux + partial-multiply segment (0007 §3's constant-split multiply and its second recombine rank are both gone).
- **Every 30/31-bit carry-propagate add is sliced at bit 16**, following the record 0012 mapper finding (carries fold in the next segment as one flat add; an adder stays an adder; no carry-select muxes): the low 16 sum bits and the carry register in one cycle, the carry folds into the carry-free high partial as one flat 15-bit add the next cycle. This applies to the product CPA, both combine ranks and the DESCALE (whose 30-bit `(x + rnd) >>> S` reduces to one 15-bit window add per output — only `[14:0]` of each output ever reached `o_flat`, so `(x + rnd) >>> S` is `x[S+14:S] + rnd[S+14:S] + carry(bits [S-1:0])`, and the pass-2 rounding constant 16384 = 2^14 makes the carry a single gate, `p2 & x[14]`).
- **The butterfly rank 2/3 chain is split**: `z1e` and `z5i` register one cycle behind `t10..t13`/`z1..z4`. Chaining them (two 17-bit adds in one segment) measured 22.4–23.1 ns; registered, each segment is one 17-bit add.
- The product registers take the same `[29:0]` slice of the same true product the 0007 §4 split multiply took; the butterflies, combine decomposition (`x7 = (pb2-pa5) + z3f` etc., with `z3f`/`z4f` the record 0003 nodes) and DESCALE windows take exactly the bits the previous schedules took.

**Bit-exactness proof** (record 0003's argument re-made, as the ruling requires): every computed value is bit-identical to record 0003's arithmetic and to `verification/golden/jpeg_golden.py`. Proven by:

- `verification/rtl/test_dct.py`, 7/7 (`run_stage.py dct`): the record 0003 worked examples (transcription tables and the T.81 block); directed extreme-value blocks (all-0, all-255, checkerboards, single-pixel extremes); **2400 seeded random blocks** (plain, word-length stress, spaced, small-delta) coefficient-for-coefficient against the 0003 transcription; **300 seeded random blocks against the golden model's `fdct_block`** (the golden-model comparison this record names); random-stall backpressure at four valid/ready mixes; the cycle-budget row of §3 below; and the Yosys no-latch/no-macro check. Transcript: `flow/records/20261118T002302Z-cb51d92/dct-suite-transcript.log` (7/7, 208.0 cycles/block streamed = 16 × 13).
- `run_stage.py top_golden`: **180/180 byte-identical** entropy-coded JPEG streams against the golden model, on the restructured netlist-bearing tree. Transcript: `flow/records/20261118T002302Z-cb51d92/top-golden-transcript.log`.
- A standalone bit-accurate Python model of the restructure (register transfers with the same slice arithmetic) matched the record 0003 reference on 40 000+ pass-1 and pass-2 vectors before RTL was written; the identity argument above covers every registered value for **every input value**, not only the ratified domain (the truncations — product `[29:0]`, DESCALE windows — discard exactly the bits the previous schedules discarded).

### 2. The measured depth is 13 cycles/vector — and both §2 halves, reported

Schedule (cycle 0 = `start` while idle; `done` at cycle 12): 0 inputs; 1 butterfly rank 1; 2 butterfly rank 2; 3 butterfly rank 3 (`z1e`, `z5i`); 4 carry-save trees → `(S, C)`; 5 CPA stage 1 (low 16 + carry, high partial); 6 CPA stage 2 → products; 7 combine rank A stage 1 (ten one-operation partials); 8 combine rank A stage 2 (fold) → A bank registers; 9 combine rank B stage 1 (four adds over the bank; `x0`/`x2`/`x4`/`x6` latch directly); 10 combine rank B stage 2 → `x1r`/`x3r`/`x5r`/`x7r`; 11 DESCALE carries; 12 DESCALE window adds → `o_flat`.

No depth was published before measurement. The measured iteration, all `flow/sta-preroute.sh --only jc_dct` on the netlist regenerated from the iteration's own RTL (cell delays only, 20 ns clock, five §10 views; each dir carries the full per-view JSON):

| Record | Shape | `ss_125C_3v00` | ≥ 0 at all five |
|---|---|---|---|
| `20261115T230902Z-2681b7c` (landed, PR #164) | 0007 §4 12-cycle: operand-muxed split multiply, two-rank butterfly, one-cycle combine | −14.2442 | no |
| `20261117T231502Z-cb51d92` | 8 cycles: CSD carry-save trees, unsliced 30/31-bit adds | −6.4778 (binder: one 30-bit combine subtract, 26.5 ns) | no |
| `20261117T235843Z-cb51d92` | 12 cycles: every carry-propagate add sliced per the record 0012 pattern | −3.1180 (binder: the rank-2/3 double add, 23.1 ns) | no |
| `20261118T001402Z-cb51d92` | 13 cycles, rank 3 left chained from R1a | −2.4087 (same chain, 22.4 ns) | no |
| `20261118T002302Z-cb51d92` (**this record's shape**) | 13 cycles, rank 3 registered | **+0.30963** | **yes** |

The decided shape's five views — worst setup slack ns, hold violations, `fmax_mhz`:

| view | setup slack (ns) | hold viol | fmax (MHz) |
|---|---|---|---|
| `ss_125C_3v00` | **+0.30963** | 0 | 50.7863 |
| `ss_n40C_3v00` | +6.72897 | 0 | 75.3521 |
| `tt_025C_3v30` | +10.1853 | 0 | 101.888 |
| `ff_n40C_3v60` | +14.3369 | 0 | 176.582 |
| `ff_125C_3v60` | +11.5912 | 0 | 118.923 |

`setup_violation_count` 0 at every view; `total_negative_hold_slack_ns` 0 at every view. **§2's assumption-free half — ≥ 0 ns at all five §10 views — is met and measured**, at the signoff view for the first time for this block (`fmax` 50.7863 MHz > the ratified 50 MHz; `jc_quant_core`'s 51.5003 was the first). Counted cycles: 218 per block, first S3 accept to last S4 beat (16 vectors × 13 + 10 fill/drain), stall-free.

**The ≥ +6.7 ns half at `ss_125C_3v00` is not met (+0.30963) and is not met by this record.** It carries the W = 0.5 interconnect assumption with record 0007 Assumption's re-derivation clause intact, and W still waits on #34's wire-aware numbers (#34/#31 both open and blocked as of 2026-11-16). The issue's own pigeonhole bound (verified by Curator against the committed records) already showed the half needs every segment ≤ 13.3 ns, i.e. ≥ 3 sub-segments of each ~34 ns chain → ≥ 14 cycles/vector → beyond §9's ceiling; this measurement adds the empirical half: the achieved segment structure (17-bit adds, 16/14-bit slice adds with carry folds, 15-bit window adds) tops out at 19.69 ns of path (slack +0.31 against the 20 ns budget), and pushing every segment under 13.3 ns would require splitting single adds, which no ≤ 13-cycle schedule permits. Per record 0007 § Assumption, a follow-up that meets the half is re-checked — not re-opened — when W is re-derived. No target is softened; options `c` and `d` stay declined.

### 3. Pricing: the stage-2 row at the measured depth, §4's band superseded

Record 0007 §4's authorized band for `jc_dct1d` (8 → 10, ≤ 12, "beyond 12 requires a new record") is superseded by this record: **the measured depth is 13 cycles/vector**, inside §9's 13.72 ceiling:

| Stage | 0007 §4 row (depth 12) | This record (depth 13) | % of 1388.9 |
|---|---|---|---|
| 2 M0 read, DCT (both passes) | 16 × 12 + 12 = 204 per block → 1224 | 16 × 13 + 12 = **220 per block → 1320** | **95.0** |

Stage 2 stays below the counted `jc_huff` floor of 1448.2 cycles/MCU (record 0008) — it does not become the frame binder against that floor. Under the ratified max-stage model (record 0005 §7, restated for the post-0009 rows by record 0013), the target-mode frame bound at depth 13 is **1,589,066 cycles = 95.3%** of the 1,666,667-cycle period (the issue's own derivation, reproduced: stage 2 binds at 96 × 13 + 72 = 1320 cycles/MCU on the merged §7 rows). The depth the §9 budget permits was exactly one cycle beyond the band, and the measurement consumed exactly that one. `verification/rtl/test_dct.py`'s `test_cycle_budget` asserts the 220-cycle row and cites this record (counted 218).

### 4. Area cost, stated

The restructure buys depth with area, as the ruling anticipated: whole-top synthesis of the candidate vs the committed landed netlist — instances 31,341 → **44,591** (+42.2%), area 1,118,900.97 → **1,519,139.87 µm²** (+35.7%) (`flow/netlist/report.json`, both at the 20 ns `ss_125C_3v00` synthesis constraint). The dominant additions are the twelve carry-save trees, the twelve staged CPA/combine banks and the A-value register bank. This record publishes the cost; whether it is worth paying is part of ratification.

## What this record does not settle

- **The +6.7 ns half** (§2 above): open until #34's wire-aware numbers re-derive W; the assumption-free half is met without it.
- **Ratification**: this record is Proposed. The restructured RTL, netlist, and the 220-cycle budget assertion land only with ratification; until then `main` keeps the 0007 §4 12-cycle `jc_dct1d` and its 204-cycle row.
- **`colour_convert`** (#132's module, allowance now 0010 §1's): untouched; this record's slicing pattern is recorded for whoever carries that issue, as 0012 recorded its mapper findings for this one.
- **The q95 cycle gap** (record 0008, remedy #137) and stage 5 bit pack: untouched; the depth-13 stage-2 row (95.0% of §9) does not move the frame binder.
- **Post-route or SPEF-annotated timing (#34) and top-level STA (#31)**: out of scope, as in 0007 and 0012.

## Rejected alternatives

- *A 13th cycle spent registering the operand mux (the two-rank butterfly + registered-mux schedule the issue marked "measured envelope unknown").* The Curator inferred ≈ 35 ns for it; this iteration did not build that variant — the CSD-tree restructure removes the mux from the multiply path entirely, which is strictly better than registering it (the mux disappeared from the binder list at candidate 1), and a measured refutation of the inference is a complete outcome per record 0007 §1's own clause.
- *Stop at 12 cycles/vector and report −3.1180 ns.* §2's escape ("one more register stage within the allowance") had exactly one cycle of allowance left (§9's 13.72 ceiling) and the measurement showed the rank-2/3 chain segment (23.1 ns) still failing; stopping would have left the met half unmet for no measured reason.
- *Re-associate the butterfly sums to shorten the rank-2/3 chain inside one cycle.* Even though two's-complement addition is associative and the registered values would not change, the registered-value identity is this record's proof obligation; splitting the chain across the existing rank-3 register achieves the same segment depth without touching the adder grouping 0007 §3 named.
- *Hand-instantiated CSA/carry-select cells.* Rejected as in 0012: the RTL-level identities reached the target; cell-level instancing would couple the netlist to one corner's gate mix.
- *A tighter ABC delay target for the whole-top synthesis.* Rejected as in 0007/0012: ABC's own critical-path estimate on the candidate is still 36.9 ns against the 20 ns target while OpenSTA measures 19.69 ns — the depth is in the RTL cuts, not in the tool run.

## Consequences

- **On ratification**, `rtl/jc_dct1d.v` (13-cycle CSD carry-save datapath), the regenerated `flow/netlist/`, and `verification/rtl/test_dct.py`'s 220-cycle assertion land on `main` together; `spec/README.md`'s status row for this record moves to Decided by its own decision record. The five record directories above stay append-only evidence.
- **Schedule consumers re-price to the depth-13 rows**: stage 2 = 1320 cycles/MCU (95.0% of §9), frame bound 95.3% at worst-case content under the merged §7 model (#136/#137's consumers; record 0013's per-depth rows extend to depth 13 by the same model).
- **`jc_dct1d`'s port list and stream contract are unchanged** (`start`/`pass2`/`d_flat`/`go`/`busy`/`done`/`o_flat`, one vector per 13 cycles held while `go` is low) — `jc_dct.v` is untouched, as are the transpose file and the S3/S4 streaming interface.
- **Frame-rate figures remain claims from counted cycles** (spec §9): nothing here is measured beyond STA and simulation on the pinned netlist, never silicon.
