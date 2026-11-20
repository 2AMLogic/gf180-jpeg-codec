# The frame-cycle re-count at the committed retime revision `3a19263` — issue #238

The November 18 frame-cycle record
(`../20261118T1800Z-frame-cycles-retime132-55a500a-wip/`) was captured
against an uncommitted working tree: its directory name's `55a500a` plus the
`-wip` suffix was the only revision hint, and `cycles.json` itself carries no
commit identifier, so the RTL revision behind the README's headline cycle
counts was not reproducibly pinned (the sibling STA record, by contrast, names
its netlist revision). This record re-runs the same bench on a **clean
checkout of the retime commit as merged** —
`3a1926313efea3a069c0c43c64ba4bb4f0f3c357`, the same revision the README's
pre-route STA evidence names — so both pieces of README evidence now pin one
common revision. The `-wip` record stays in place, append-only and untouched.
All figures are **simulated**, never measured (spec §9, CLAUDE.md).

## Result

Testbench `verification/rtl/test_top_frame_cycles.py` (launched as
`python3 verification/rtl/run_stage.py top_golden --test-module
test_top_frame_cycles`, the documented one way to launch every bench; runner
exit 0, **3/3 pass**), three rows, colour 4:2:0 at 640 x 480 (exactly 1200
MCUs, no host padding). Machine-written figures are in `cycles.json`; the
bench's `"issue": 119` field inside it is the schema-2 stage-counter
provenance and stays as the bench wrote it — this run is issue #238's.

| Image | Quality | Output bytes | Cycles to `out_last` | % of frame period (1,666,667) | % of record 0005 bound (1,503,668) | Byte-exact vs golden |
|---|---|---|---|---|---|---|
| `scene_fbm` | 50 | 18,616 | **1,383,296** | 83.0 | 92.0 | yes |
| `noise_max_entropy` | 50 | 126,543 | **1,383,299** | 83.0 | 92.0 | yes |
| `noise_max_entropy` | 95 | 360,997 | **1,383,350** | 83.0 | 92.0 | yes |

Every row is inside the §9 floor/ceiling band (921,600 – 1,666,667 cycles)
with `golden_match` true. Derived frame rates at the §9 signoff clock of
50 MHz (`50e6 / cycles per frame`, **simulated**, never measured): **36.1
frames/s** on every row, against the 30 frames/s target — a 1.20x margin.

## Provenance

Run on 2026-11-20 at 02:32–02:58 UTC from a clean detached checkout of the
retime commit (a throwaway `git worktree`, not a development worktree):

- `git rev-parse HEAD` → `3a1926313efea3a069c0c43c64ba4bb4f0f3c357`
- `git status --porcelain` → empty, verified **before** the run and again
  after it (the bench's `sim_build/` scratch is gitignored)
- invocation, from the checkout root, with the JSON directed to an absolute
  path outside the checkout:

  ```sh
  FRAME_CYCLES_JSON=/tmp/issue238-out/cycles.json \
    python3 verification/rtl/run_stage.py top_golden \
    --test-module test_top_frame_cycles
  ```

  (`/tmp/issue238-out/cycles.json` copied here unmodified, sha256
  `7f0f90b7519dcc51e5f9cfd0b45c606b8078557ea32e006c0657144bd9220529`.)
- runner exit 0, cocotb seed 1 (the bench-supplied default), `status_error` 0
  at the end of each frame.

Environment, disclosed: Icarus Verilog **13.0** (v13_0) with cocotb **2.0.1**
and Pillow **10.2.0** for the decode cross-check, Python 3.12 (the host
interpreter), on a shared dispatch host — one local `run_stage.py` invocation,
no parallel fan-out. (The depth-12 record's run used cocotb 2.1.0; the engine
version here is the one these figures came from.) This is not the
README-pinned OSS CAD Suite 14.0 toolchain; the figures are labelled
simulated and cite the engine they came from. Wall time 464.8 / 557.9 /
535.5 s per row.

## Relation to the November 18 `-wip` record

The committed revision reproduces the WIP counts **exactly**: this run's
`cycles.json` and
`../20261118T1800Z-frame-cycles-retime132-55a500a-wip/cycles.json` are
byte-identical except the three `wall_time_s` fields — every counted figure
(`cycles_to_out_last` 1,383,296 / 1,383,299 / 1,383,350, all nine stages'
`stage_counts`, the stage-sample windows, `output_bytes`, `golden_match`)
matches, so there are no count differences to report by image or quality.
The uncommitted tree the WIP run captured was, as far as this bench observes,
the tree that landed as `3a19263`. Counts are machine-written and exact to
±1 as this bench computes them (positional within a simulation — see the
depth-12 record's "Disposition" section for the residue analysis; the same
ordering and windows recur here, so the WIP figures and these agree at the
same positions).
