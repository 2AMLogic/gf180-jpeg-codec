# gf180-jpeg-codec — agent instructions

Open-source canary block: a baseline JPEG encoder plus a QOI-class lossless
path on the gf180mcu PDK, designed and verified by AI agents. **Digital.**

- **PDK**: gf180mcu (open PDK, google/gf180mcu-pdk); pin the same variant and
  `open_pdks` revision as `gf180-sram` unless a decision record says
  otherwise. Digital flow: cocotb + Icarus for simulation, Yosys for
  synthesis, OpenROAD for place-and-route and timing. Layout, DRC, and LVS
  through klayout-tools (`klt`).
- **Buffering is the central risk.** 4:2:0 coding works on 16-line strips;
  buffering a strip of a 640-pixel-wide image on chip is tens of kilobytes,
  far more than one fleet SRAM instance holds. Decide the input order early:
  raster input with an on-chip strip buffer, or block-ordered input where the
  host supplies 16 x 16 macroblocks and the chip buffers only one. That
  choice sets the memory, the floorplan and the host interface, and it goes
  in a decision record before RTL.
- **Byte-exact or nothing.** The golden model is a software encoder,
  committed in this repo, with the same colour conversion, DCT arithmetic,
  rounding, tables and framing as the RTL. RTL output must match it byte for
  byte. Decodability by a reference decoder is a second, independent check,
  not a substitute. Fixed-point DCT precision is where a near-miss hides;
  specify it bit for bit.
- **Scope discipline.** Baseline sequential JPEG only — no progressive, no
  arithmetic coding. No processor, no camera or display interface. No SRAM
  macro is designed here: buffers use `gf180-sram`'s macro (its interface
  as ratified in its `spec/sram.md`) or standard-cell RAM, chosen by
  adopt-or-record under the fleet's reuse rule (a block is designed once)
  and pinned in `reuse.lock.json`.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail out of it and describe
  the gap, not the design.
- **Verification is the product**: no claim without a testbench. Frame-rate
  claims are derived from the signoff clock and cycles per frame counted in
  simulation on a named image — never call a simulated figure measured.
  Recorded results are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not relax
  the ratified spec to make results pass.
- **640 x 480 at 30 frames/s, 4:2:0, is the target.** Greyscale 320 x 240 at
  15 frames/s is the fallback and 1280 x 720 at 30 frames/s plus a decoder is
  a stretch. Do not let the decoder drive the architecture before the encoder
  closes.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.

Work is coordinated through `loom:` labels on issues and pull requests, and the same roles run either under `loom-daemon` or by hand in an attended session — daemon mode is optional. Create the labels once with `.loom/scripts/sync-labels.sh` (an install ships `.github/labels.yml` but does not create the labels on the forge). A pull request ready for review carries `loom:review-requested`; Judge reviews it and applies `loom:pr` (approved) or `loom:changes-requested`; Doctor fixes a `loom:changes-requested` pull request and returns it to `loom:review-requested`. Only a `loom:pr` pull request gets merged, and always via this repo's merge script (`.loom/scripts/merge-pr.sh`) — never a raw forge merge command such as `gh pr merge`. Full state machine: `.loom/docs/label-state-machine.md`.
<!-- END LOOM ORCHESTRATION -->

<!-- BEGIN REPO-SKILLS -->
This repository has [Repo Skills](https://github.com/rjwalters/repo) v0.24.7 installed —
general repository hygiene and environment commands invoked as `/repo:<command>`. Run
`/repo:help` for the command list, or see `.claude/skills/repo/SKILL.md` for the full
guide. Hygiene commands apply safe, reversible fixes by default and report each
change; run with `--ask` to review first, and `--prune` to allow irreversible
removals. Managed by `install.sh` — edit outside the markers only.
<!-- END REPO-SKILLS -->
