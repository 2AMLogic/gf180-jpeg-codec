# Gate-level smoke run, issue #89 (re-generated report)

Supersedes `../20261105T053856Z-24bab41/`, whose `report.json` was committed as a
0-byte file and is not evidence. That record is left in place (append-only); this
one holds the real `klt functional-verification` report from a fresh run.

Same netlist (`netlist.sha256`: `871dc5df…`, matches `flow/netlist/jpeg_codec_top_synth.v`),
same four testcases, same seed (1), same sources as the earlier record. Result: all
4 passed, 0 failed, 0 skipped (`report.json`, `status: pass`, Icarus 13.0, cocotb 2.1.0,
no SDF). Sim times / real seconds: colour_decodes 51990 ns / 20.9 s, colour_padded_size
68330 / 27.7, grey_decodes 33610 / 4.7, colour_with_stalls 57920 / 17.4.

Not re-run here: `test_qoi_decodes` (known gate-level divergence, #93) and the
controls described in the earlier record README, which still apply.

## Reproducing

`request.json` paths are repo-root-relative (`$PDK_ROOT` stands for the pinned
`gf180mcuD` tree, i.e. `~/.ciel` in the as-run case; substitute it before use).
Prefer regenerating the request with
`python3 verification/rtl/run_top_smoke_gl.py --klt-request <dir> --testcase <list>`
and running it from the repo root with
`PYTHONPATH=verification/golden:verification/tb`.

Run command (a throwaway env, since the host klt has no matching cocotb):
`uvx --from "klayout-tools[functional-verification]" --with pillow klt functional-verification request.json -o <dir> --format json > report.json`
(klt 0.9.0; the as-run request had absolute worktree paths, rewritten here).

## Why the first report was empty

Pointing `PYTHONPATH` at a user site-packages shadows klt's own modules
(`rpds` import failure) or loads a cocotb built for another CPython (simulation
segfault, exit -11); klt then wrote nothing to stdout. Tool gap to be filed
on `2AMLogic/klayout-tools` (see the PR comment).
