# 0001: PDK pin

- **Status**: proposed
- **Date**: 2026-10-17
- **Decided by**: builder agent, from issue #5 (pending human ratification)

## Context

Every evidence record in this repo is stamped with the PDK it ran on, and
nothing pinned a PDK yet (klayout-tools T1 checklist, item 9). `CLAUDE.md`
says to pin the same variant and `open_pdks` revision as `gf180-sram`, and the
gf180mcu canaries are being re-pinned together (2AMLogic/gf180-pll#788).

## Decision

- Variant: `gf180mcuD` (5-layer-metal; routes Metal4 and Metal5).
- `open_pdks` revision: `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7`.
- Installer: ciel 2.6.1, i.e.
  `uvx --from ciel==2.6.1 ciel enable --pdk-family gf180mcu f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7`.
- PDK root: `~/.ciel`.
- `flow/pdk.env` exports the pin and fails when the resolved tree's `SOURCES`
  file names a different `open_pdks` revision.

## Alternatives considered

- **A 3LM variant (`gf180mcuA`)**: cannot route Metal4 or Metal5; see
  2AMLogic/gf180-polysynth `spec/decision-records/0001-pdk-selection-gf180mcu.md`.
- **A `~/.volare` tree**: not pinned by a `SOURCES` revision check; `pdk.env`
  rejects any tree whose revision differs, so a stale one is never used silently.

## Consequences

Every later record names this revision. A re-pin is a new decision record and
re-runs the smoke flow in `flow/smoke/`. The standard-cell library used by the
smoke flow (`gf180mcu_fd_sc_mcu9t5v0`) is provisional; #3 decides the codec's
own library and supply.
