# verification

cocotb benches, driven through the runner vendored from
`2AMLogic/gf180-polysynth` (pinned in `/reuse.lock.json`; divergences in
`spec/decision-records/0001-harness-divergence.md`).

## Simulator versions

The pinned toolchain is Icarus Verilog 14.0 and Verilator 5.053 (OSS CAD Suite
2026-09-16), with cocotb 2.1.0. Ubuntu's apt Verilator cannot build cocotb
2.1's shim, so do not use it.

## Cold start

```sh
bash .github/scripts/install-oss-cad-suite.sh      # -> ~/oss-cad-suite
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install cocotb==2.1.0

python3 verification/common/run_tb.py --sim icarus
python3 verification/common/run_tb.py --sim verilator
bash verification/tb/negative_control.sh           # injected bug must exit exactly 1
bash .github/scripts/lint.sh
```

`run_tb.py` exit status: `0` all tests passed, `1` the suite ran and a test
failed, `2` the suite did not run (build error, import error, empty results).
A negative control must require exactly `1`.

`verification/tb/test_smoke.py` drives `rtl/smoke_placeholder.v`, a stand-in
that is not the codec.

## Status

The skeleton was run here on Icarus 13.0 and Verilator 5.050 (host versions),
not the pinned 14.0 / 5.053.
