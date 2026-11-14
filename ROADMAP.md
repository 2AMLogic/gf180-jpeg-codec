# Roadmap

`gf180-jpeg-codec` is a baseline JPEG encoder plus a QOI lossless path on the
gf180mcu open PDK, carried from a ratified spec to a routed, verified layout.

Status as of 2026-11-13, `main` @ `228d619`.

## Where it stands

On the README's maturity ladder the block has passed "RTL byte-exact on the
reference image set" and is stopped before "synthesized with timing met": a
gate-level netlist exists, but nothing has been timed and nothing is routed.

Done and evidenced on `main`:

- **Spec**: `spec/codec.md` (ratified 2026-10-17), decision records 0002 to 0006.
- **Golden models**: `verification/golden/jpeg_golden.py` and `qoi_golden.py`,
  cross-checked against libjpeg-turbo and the vendored `qoi.h`
  (`verification/records/crosscheck-*.json`; odd sizes per record 0006, PR #86).
- **RTL**: 20 modules under `rtl/`, top `jpeg_codec_top` (#42 to #48), with
  per-stage cocotb benches under `verification/rtl/`.
- **Byte-exact at RTL**: the 180-case top-level suite against the golden
  models, with a failing negative control
  (`verification/records/top-golden-*.json`, #88, PR #91).
- **Gate-level netlist**: `flow/netlist/jpeg_codec_top_synth.v` (Yosys,
  31,341 instances, the three SRAM macros left as black boxes), and the same
  180 cases passing on it at zero delay
  (`verification/records/20261106T1803Z-golden-gl-e32b0e8/`, #102, PR #103),
  after the fix of a gate-level X on the QOI path (#93, PR #95).

Against the T1 checklist tracked in #4, the committed verdict
(`manifests/gf180-jpeg-codec.signoff.json`, klt 0.8.0) reads 3 met, 1 not
applicable, 7 unmet of 11:

| Item | State | Evidence or blocker |
|---|---|---|
| 1 Design sources | met | `manifests/attest/item1.json` (#30) |
| 2 Layout | unmet | #31, held on the SRAM macro LEF |
| 3 DRC clean | unmet | #32, needs #31 |
| 4 LVS clean | unmet | #33, needs #31 |
| 5 Corner verification | unmet | functional half committed but uncited (`manifests/README.md`); STA half is #34, needs #31 |
| 6 Monte Carlo | not applicable | `manifests/codec-item6-statement.json` (#35) |
| 7 Post-layout verification | unmet | #36, needs #31 and #34 |
| 8 Characterization report | unmet | #37, needs #34 and #36 |
| 9 Testbenches shipped | met | `manifests/attest/item9.json` (#38) |
| 10 Repo hygiene | met | `manifests/attest/item10.json` (#39) |
| 11 Power delivery | unmet | #40, needs #31 and #33 |

The one place-and-route attempt (`flow/records/20261028T050500Z-a53678d/`,
PR #77) stops at floorplan, `LEF master gf180_sram_256x32 not found`:
`gf180-sram` publishes a LEF for the array core only (`flow/README.md`).

## Now

Work that does not need the SRAM macro views. None has an approved issue yet.

1. **Bring the status text in line with `main`.** `README.md` still says the
   golden model, RTL and layout "are not started"; `spec/README.md` says
   record 0001 is not committed and omits two later records; the gate-level
   smoke section of `verification/README.md` predates PR #95. Done when each
   matches the tree and the item 10 attestation and signoff record are
   regenerated in the same PR.
2. **Count cycles per frame on the two named 640 x 480 images.** Spec §9
   requires any frame-rate figure to come from cycles counted in simulation
   on `noise_max_entropy_640x480` (worst case) and `scene_fbm_640x480`
   (typical); none is committed, and the 180-case suite defers 640 x 480.
   Done when a record under `verification/records/` gives the counted cycles
   for both, colour 4:2:0, against the 1,666,667-cycle frame period and the
   1,503,668-cycle bound of record 0005 §7, labelled simulated.
3. **Pre-route timing of the standard-cell logic at the five §10 views.**
   Nothing has been timed. Done when a record under `flow/records/` gives the
   worst setup and hold slack per view for the synthesized netlist with the
   macros black-boxed at the 20 ns clock, stated as not item 5 evidence; or
   when the tool's refusal of an unrouted netlist is recorded instead.
4. **Measure the size of decision 0004's option C.** The record leaves the
   standard-cell RAM area "not estimated here (unverified)". Done when a
   synthesis-only record gives instance count and cell area for
   `jpeg_codec_top` with the three 256 x 32 memories as standard cells,
   leaving the committed netlist and the decision unchanged.
5. **Extend the top-level golden suite to the deferred cases.** Non-MCU sizes
   (`odd_100x60`) and stalled-port runs are covered only by the smoke bench.
   Done when both are byte-exact cases in `test_top_golden.py` with a new
   report under `verification/records/`.

## Next

Unblocked when `gf180-sram` publishes the full-macro LEF and GDS
([gf180-sram#199](https://github.com/2AMLogic/gf180-sram/issues/199)):

- **#31 Layout.** Add the three `macros[]` entries (M0/M1/M2, spec §13) to
  `flow/place-and-route.json`, pin the macro files in `reuse.lock.json`, and
  commit a routed GDS that the request reproduces with `power.pdn: true`.
  The run also settles what `flow/README.md` lists as unmeasured: PDN reach
  to the macro supply pins, and halo versus strap overlap.
- **#32 DRC** and **#33 LVS** on that GDS, then **#40** (`klt erc` supply spec).
- **#34 Five-view STA.** Needs the routed design and the macro's Liberty views
  at the §10 views; cited together with the committed functional report so
  item 5 can grade.
- **#36** SDF-annotated re-run of the 180 cases on the post-route netlist,
  then **#37** the characterization report (Fmax, area, power).

## Later

- **Does the macro close the access budget?** Record 0005 budgets every SRAM
  access at A = 2 cycles, to be checked against the macro's Liberty
  clock-to-Q at the ss views once those exist.
- **Stretch row (1280 x 720, 100 MHz).** First question: what Fmax the routed
  target design reaches (#37); record 0005 notes two stages exceed the
  stretch budget at worst-case content.
- **Decoders (JPEG and QOI).** Deferred by spec §14 until item 5 closes.
- **Shuttle seat and measured silicon.** The last ladder rungs; no seat is
  recorded, and the question first is whether post-route STA closes.

## Blocked and waiting

- **The whole T1 path waits on another repo.** #31 is held on
  gf180-sram#199 (full-macro LEF, open, last updated 2026-10-18), which waits
  on that repo's macro assembly (gf180-sram#201 and #247, both open). The
  hold was confirmed on #31 on 2026-10-29.
- **Decision 0004's gate is open.** Without a LEF and Liberty views the
  record moves the affected contents to standard-cell RAM through a new
  decision record. Waiting or invoking that gate is a maintainer decision;
  Now item 4 supplies the missing number. Record `0001-pdk-pin.md` also
  still reads "proposed".
- **Nothing here is dispatchable today**: every open issue is blocked except
  the #4 tracker, whose body still describes the empty tree of 2026-10-17 and
  needs an edit to match the table above; the Now items are not yet filed.

## Not planned

Progressive or arithmetic-coded JPEG, a processor, a camera or display
interface, and designing an SRAM macro in this repo (README scope).
