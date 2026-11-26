# VGA frame counts for the 13-cycle DCT

These simulations ran on `c04ef0945faa1a4ce11b0fb2f88aac17cda45f3c`,
which contains the depth-13 RTL from `49ecc4e`. Each case drives a 640 × 480
colour 4:2:0 frame with the output ready throughout. Pixel stalls count clock
edges with `pix_valid && !pix_ready`. Frame cycles run from frame start
through the transfer of `out_last`. [Per-stage counters and JPEG checks](cycles.json).

| Image | Quality | Cycles to `out_last` | Pixel stalls | JPEG bytes |
| --- | ---: | ---: | ---: | ---: |
| `scene_fbm` | 50 | 1,498,496 | 574,932 | 18,616 |
| `noise_max_entropy` | 50 | 1,498,499 | 574,932 | 126,543 |
| `noise_max_entropy` | 95 | 1,498,550 | 574,932 | 360,997 |

Each JPEG matched the golden encoder byte for byte and decoded to 640 × 480 RGB.
The slowest row finished 168,117 cycles inside the 1,666,667-cycle VGA30 period.

## Reproduction

The capture used Icarus Verilog 13.0, cocotb 2.0.1, Python 3.12.3 and
Pillow 10.2.0, with the runner's default seed of 1. These commands reproduce
the rows from the repository root, each in a fresh simulator process.

```sh
for testcase in test_scene_fbm_q50 test_noise_max_entropy_q50 test_noise_max_entropy_q95
do
    FRAME_CYCLES_JSON="$PWD/verification/rtl/sim_build/$testcase.json" \
        python3 verification/rtl/run_stage.py top_golden \
        --test-module test_top_frame_cycles --testcase "$testcase" || exit 1
done
```

The bench writes each observation before checking the pixel-stall ceiling.
At `c04ef09` all three cases exceeded the depth-12 ceiling of 459,994.
The record collects those three original row objects under their common
schema-2 header. The absolute sample windows are local to each process.
With the regression reading its ceilings from this record, all three cases
passed on a second run. Each output row reproduced every field except wall time.
