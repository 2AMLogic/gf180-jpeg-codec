# Decision record 0008: the Huffman cycle budget versus the counted `jc_huff` floor

**Status**: Decided, option A (agent-decidable; 2026-11-15, issue #119)
**Resolves**: #119 (the per-stage count and its disposition; the q95 gap's closure is deferred to #137)
**Spec**: `spec/codec.md` §9 (unchanged); amends `spec/decision-records/0005-rtl-microarchitecture.md` §7 (via #136)

Filed as 0008, not 0007: the 0007 slot was claimed in flight by #127's
`0007-pre-route-setup-shortfall.md` (open, `loom:building`, referenced by
child #131) after this issue's curation stamped "0006 is the highest number
committed".

## Question

Simulation of the ratified §9 target row (640 x 480, 4:2:0, 30 frames/s at
the 50 MHz signoff clock) shows `noise_max_entropy_640x480` at quality 95
needing 1,740,070 cycles to `out_last` — 104.4% of the 1,666,667-cycle frame
period (28.7 frames/s simulated), above every single-stage budget row in
record 0005 §7 and 15.7% above §7's derived frame bound. Which disposition
does the counted evidence support: correct the broken budget row, change the
RTL, or re-scope the §9 target row's quality range?

## Evidence

Per-stage count, `verification/records/20261115T0046Z-frame-stages-61644ee/`
(RTL cocotb simulation, Icarus 13.0, seed 1, non-intrusive: the three rows'
committed cycle and byte figures reproduce exactly; every figure below is
**simulated**, never measured):

- The binding stage at worst-case content is **`jc_huff`**, not stage 5 as
  record 0005 §7's "Slowest stage" paragraph claims. Walking the pipeline
  from the output inward, `s7` (jc_huff → jc_bitpack) stalls 9 cycles at q95
  and `bp` / `out` stall 0 — jc_bitpack and jc_out_mux are exonerated —
  while `s6` (jc_quant → jc_huff) stalls 1,268,261 of the 1,740,071 true
  frame cycles (72.9%); everything upstream is backed up behind it.
- The cost is `jc_huff`'s four-state blocking FSM, not memory: every symbol
  pays `ST_IN` → `ST_ISSUE` → `ST_WAIT` → `ST_OUT`, at least 4 cycles, plus
  1 cycle per in-run zero. A golden-model tally predicts a floor of
  1448.2 cycles/MCU at q95 (1,737,840 cycles over 1200 MCUs); the counted
  true frame count is 1,740,071 — the floor plus 2,231 cycles (0.13%) of
  header, fill and drain. Confirmed.
- Record 0005 §7 row 4 ("Huffman symbol path", 952 cycles/MCU) prices about
  2.1 cycles per symbol — roughly half the FSM's real cost. The counted q95
  frame is 1450.06 cycles/MCU, 1.52x the budgeted row. **The row does not
  bound the design: it is a broken budget.**
- Memory and arbitration are exonerated: `m1_en` occupancy at q95 is
  342.8 cycles/MCU against §7's 708-cycle M1 row (loose, not broken);
  `hf_m1_req && !hf_m1_gnt` stalls 9 cycles at q95; the quantizer holder's
  `qa_pend && !qa_gnt` stalls 4,826.
- At the reset-default q50 the §9 row is met on both §9 images with 1.5x to
  1.7x margin (58.9% / 66.2% of the period); at `scene_fbm` q50 the DCT
  binds, loosely, exactly as §7 predicts for typical content. The gap is
  q95-only, and q95 is a legal configuration of the ratified spec (§5
  host-scaled Annex K).

## Options

- **A. Correct record 0005 §7's affected row(s)** (chosen). A budget that
  does not bound the real design is a broken budget (CLAUDE.md: agents do
  not relax results to pass; budgets are evidence too). Gives up: nothing —
  the correction makes the q95 shortfall explicit in the budget instead of
  hiding it inside a wrong row.
- **B. An RTL change to the binding stage that closes the gap at q95.**
  Rejected as *this* record's disposition: it is a microarchitecture change
  (pipelining `jc_huff`'s symbol path) that must be co-decided with #127 —
  #127 buys clock period by spending cycles, so its pipeline-depth decision
  sets the cycle cost this count establishes, and deciding the RTL direction
  unilaterally here would preempt it. Filed as #137, to be decided with
  #127's record.
- **C. A `spec/codec.md` §9 note on the quality range the target row
  covers.** Rejected: it changes what the ratified §9 target row means —
  declaring q95 outside the target is the "relax the ratified spec to make
  results pass" move CLAUDE.md forbids, and needs an operator ruling
  (precedent: record 0006) — while the gap is plausibly closable by option
  B's RTL change, so the operator step is not yet warranted.

## Decision

Option A. The correction itself is #136's task (a separate change, keeping
this record one measurement plus one decision): re-derive §7 row 4 from the
FSM floor (content-dependent, ~1448–1460 cycles/MCU at worst-case content),
name stage 4 the binding stage at worst-case content, and restate the frame
bound honestly — with the corrected row, the worst-case-content budget
exceeds the §9 1388.9 cycles/MCU budget, which is the counted truth. §9's
ratified target row is untouched. The q95 gap stays open and owned: #137
(RTL remedy, co-decided with #127); if #137's direction fails or #127's
depth decision makes it uneconomical, an operator ruling on a §9
quality-range note (option C) is the remaining path.
