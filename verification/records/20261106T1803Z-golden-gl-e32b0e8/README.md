# Gate-level golden run, issue #102

The 180-case byte-exact suite `verification/rtl/test_top_golden.py` (colour, grey
and QOI; golden models `jpeg_golden.encode` / `qoi_golden.qoi_encode`) run against
the committed synthesized netlist, zero delay, no SDF.

- Netlist: `flow/netlist/jpeg_codec_top_synth.v`, sha256 `e32b0e8b820d07887a6b19d81b3beb63bffe334dabdcd66c04c8f7d227d8c3ee`
  (`netlist.sha256`; equals the file on this PR's head). This is the netlist after
  PR #95; the earlier smoke records name `871dc5df…` and do not cover it.
- Result (`report.json`, `status: pass`): `test_count` 180, `passed_count` 180,
  `failed_count` 0, `skipped_count` 0. Icarus 13.0, cocotb 2.1.0, seed 1.
  This is simulated evidence, not a measured figure.
- Not split: one `klt functional-verification` run, one cocotb process, sequential.
  Wall time 106 min 42 s on a shared host (load ~25-30), about 20 s per small case
  and minutes for the 64 x 48 textured images.
- No gate-level vs RTL mismatch was found, so no RTL/netlist finding is filed. The
  golden model was not touched.

## Reproducing

`request.json` paths are repo-root-relative; `$PDK_ROOT` stands for the pinned
`gf180mcuD` tree (`~/.ciel` as run). Regenerate the request with
`python3 verification/rtl/run_top_smoke_gl.py --klt-request <dir> --test-module test_top_golden`
and run it from the repo root:
`PYTHONPATH=verification/golden:verification/tb uvx --from "klayout-tools[functional-verification]" --with pillow klt functional-verification <dir>/request.json -o <out> --format json > report.json`
(klt 0.9.2.dev, throwaway uvx env).

## Negative control

`python3 verification/rtl/run_top_smoke_gl.py --inject-fault --test-module test_top_golden --testcase "test_qoi_golden/case=('flat_gray_128', 64, 48)"`
(every `xor2_1` replaced by `or2_1` in a temp copy of the netlist; run in a venv with
cocotb 2.1.0) ran 2 cases (see below), both FAIL (`0/2 passed`) and **exited 1**,
as required (1 = the suite ran and tests failed).

Note on `--testcase`: cocotb names the parametrized cases `test_x/case=<n>` where
`<n>` is the repr truncated at the first comma, so this filter matched the colour
and grey cases `case=64` rather than a QOI case; only the verdict (suite ran,
tests failed, exit 1) matters for the control. Without cocotb installed the
script also exits 1 from an import traceback; check for the `0/N passed` summary.
