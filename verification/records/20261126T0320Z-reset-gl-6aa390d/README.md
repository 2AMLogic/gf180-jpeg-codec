# Gate-level reset and golden case 47 after the DCT merge

This run combines the table-loader reset from `94c238f8` with the
depth-13 DCT on `main` at `b6d05f3`. Synthesis used klt 0.9.2,
Yosys 0.67+post (`b8e7da6f`) and the gf180mcuD PDK pinned in
`flow/pdk.env`. The SHA-256 of `flow/netlist/jpeg_codec_top_synth.v` was
`6aa390d0340fb57f977a7a89c1d8508e0e3d087ccd9664c252f6ac4108acb69c`.
The item-1 attestation ran `flow/synthesize.sh --check` and returned a pass.

Both tests used Icarus 13.0, cocotb 2.1.0 and seed 1.

| Test | Zero-delay gates | RTL control |
| --- | --- | --- |
| Reset with no host traffic | PASS at 26,840 ns | PASS at 26,840 ns |
| Colour golden case 47 | PASS at 54,200 ns, 2,145 frame cycles | PASS at 54,200 ns, 2,145 frame cycles |

The reset bench sampled known status pins and error cause on every cycle
through idle, when `(status_idle, status_busy, status_error)` was `(1, 0, 0)`.
Case 47 encoded the 16 × 16 `checker_1px` image at quality 95. Both runs
matched all 787 bytes from `jpeg_golden.encode`, whose SHA-256 was
`5d764502e9803a630623ab763fb832447037c58f50a55d4b13718c6ee5c4ca6c`.

Run from the repository root with the pinned PDK installed.

```sh
sha256sum flow/netlist/jpeg_codec_top_synth.v
python3 verification/rtl/run_top_smoke_gl.py --testcase test_reset_reaches_known_idle
python3 verification/rtl/run_top_smoke_gl.py --test-module test_top_golden --testcase 'test_colour_golden/case=47'
python3 verification/rtl/run_stage.py top_smoke --testcase test_reset_reaches_known_idle
python3 verification/rtl/run_stage.py top_golden --testcase 'test_colour_golden/case=47'
```
