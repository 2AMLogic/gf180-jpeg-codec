# 0001 — Harness divergence from gf180-polysynth

- Status: accepted
- Issue: #6
- Master: `2AMLogic/gf180-polysynth` @ `010efac225b6173105bfb4a13dcbf1b94121ec6f`

## Context

The org reuse rule (a block is designed once) makes gf180-polysynth the master
for the cocotb runner and CI helpers. They are vendored under
`reuse.lock.json`. Two of the three files cannot be used byte for byte
because they name polysynth's own modules and layout.

## Decision

| File | Divergence | Why |
|---|---|---|
| `verification/common/run_tb.py` | `ROOT` is one directory deeper; `TB` is `verification/tb`; `SOURCES`, `TOPLEVEL` and the test module name the placeholder (`smoke_placeholder`, `test_smoke`); the `--nv` option and the `parameters`/`SYNTH_NV` plumbing are removed; comments and the usage text are updated. | Upstream hard-codes polysynth's RTL, top level, test module and the `NV` parameter. The exit-code contract (0 pass, 1 failed, 2 did not run) and the `PYTHONPATH`/`sys.path` workaround for cocotb 2.1 are unchanged. |
| `.github/scripts/lint.sh` | Python compile list, Verilator lint target, and the generated-ROM step are replaced or removed; step 6 (host-path leak) also excludes `.agents/`. | Upstream steps 1, 4, 5 are block-specific. Only the PDK-free legs are kept. `.agents/` is vendored agent tooling like `.loom/` and `.claude/`. |

`.github/scripts/install-oss-cad-suite.sh` is byte-identical to upstream and
has no divergence entry.

When the golden model lands, `run_tb.py` will change again (sources, top
level, `REFERENCE` path); that edit stays under this record.
