"""Cycles per frame at 640 x 480, colour 4:2:0 (issue #113, spec section 9).

spec/codec.md section 9 requires that any frame-rate figure be derived as
`signoff clock / cycles per frame`, with cycles per frame **counted in
simulation** on a named section 12 image: `noise_max_entropy_640x480` is the
worst case and `scene_fbm_640x480` the typical case. Decision record 0005
section 7 gives a derived bound (1,503,668 cycles, 90.2% of the 1,666,667-cycle
frame period at 50 MHz and 30 frames/s) and says itself that it is a budget,
not a result. This bench produces the result.

Three rows, colour 4:2:0 only, all at 640 x 480 (exactly 1200 MCUs, so no host
padding):

    scene_fbm          q50   typical content, the reset-default quality
    noise_max_entropy  q50   worst-case content at the same quality
    noise_max_entropy  q95   the output-side stress row (largest real output)

Every figure here is **simulated**, never measured.

What each row checks
--------------------
* The generated PPM is sha256-checked against `verification/images/SHA256SUMS`
  before it is encoded (`load_image`, shared with `test_top_golden.py`).
* The host never stalls: `out_ready` is held at 1 for the whole run and
  `pix_valid` is held at 1 until the last pixel byte is accepted. Both are
  *asserted*, not assumed (`CycleHost.out_stalls` / `.pix_gaps`).
* `status_error` is 0 at the end of the frame.
* The output decodes in Pillow 10.2.0 with warnings fatal, at size
  (640, 480) and mode RGB.
* The output is byte-identical to `jpeg_golden.encode`. A mismatch is a
  finding; the golden model is never adjusted (CLAUDE.md, spec section 11).
* The cycle count lies inside the mechanical floor/ceiling
  [921,600, 1,666,667] - the floor is ingest at 768 cycles/MCU with no stalls
  (record 0005 section 7 stage 1), the ceiling is the frame period. A figure
  outside that range is a finding to file, not something to tune away.

Why a separate module
---------------------
`test_top_golden.py`'s 180 cases and their committed records
(`verification/records/top-golden-*.json`, 180/180/0/0) must stay
byte-reproducible, so neither it nor `test_top_smoke.py` is touched. Run this
module through the existing runner:

    python3 verification/rtl/run_top_golden.py --test-module test_top_frame_cycles

Each test appends a row to a machine-written JSON file so the record quotes a
committed number instead of a hand-transcribed log line. The path is
`$FRAME_CYCLES_JSON`, defaulting to
`verification/rtl/sim_build/frame_cycles.json` (gitignored scratch); copy it
into the record directory.
"""

import json
import os
import sys
import time

import cocotb
from cocotb.triggers import RisingEdge

HERE = os.path.dirname(os.path.abspath(__file__))
for sub in ("..", "../golden", "../images"):
    p = os.path.normpath(os.path.join(HERE, sub))
    if p not in sys.path:
        sys.path.insert(0, p)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import jpeg_golden  # noqa: E402
from test_top_smoke import (  # noqa: E402
    Host, REG_CMD, CAP, colour_stream, decode_jpeg,
)
from test_top_golden import first_diff, load_image, load_quant  # noqa: E402

W, H = 640, 480

# spec section 9 target row: 50 MHz signoff clock, 30 frames/s.
CLOCK_HZ = 50_000_000
FRAMES_PER_S = 30
FRAME_PERIOD = 1_666_667                                # spec section 9 writes 50e6/30 as this
RECORD_0005_BOUND = 1_503_668                           # record 0005 section 7

# Mechanical floor: 1200 MCUs x 768 input-bus cycles per MCU (record 0005
# section 7 stage 1) = the pixel stream length, one byte per cycle at best.
CYCLE_FLOOR = (W // 16) * (H // 16) * 768               # 921,600
CYCLE_CEILING = FRAME_PERIOD

OUT_JSON = os.environ.get("FRAME_CYCLES_JSON") or os.path.join(
    HERE, "sim_build", "frame_cycles.json")

_ROWS = []


class CycleHost(Host):
    """`Host` that timestamps the `out_last` beat and forbids host stalls.

    `Host.cycles` is frame start to `status_idle`, a strict superset of the
    figure spec section 9 asks for: `Host.out_monitor` sets `last_seen` on the
    `out_last` beat but takes no timestamp, and `run_frame` computes `cycles`
    only after `wait_idle()`. Reusing it would report a number slightly larger
    than this record claims - exactly the near-miss spec section 11 warns
    about. So this subclass records the sim time of the `out_last` beat and the
    record names both reference points.

    `run_frame` below mirrors `Host.run_frame` with the random gaps removed
    (this bench is the no-stall case by definition) and the two stall counters
    added. `in_gap` / `out_gap` are pinned at 0.
    """

    def __init__(self, dut, seed=1):
        super().__init__(dut, in_gap=0.0, out_gap=0.0, seed=seed)
        self.start_ns = None
        self.last_ns = None
        self.out_stalls = 0
        self.pix_gaps = 0
        self.drive_cycles = 0

    async def out_monitor(self):
        """Hold `out_ready` high for the whole run and timestamp `out_last`."""
        d = self.dut
        while True:
            d.out_ready.value = 1
            await RisingEdge(d.clk)
            if d.out_ready.value != 1:
                self.out_stalls += 1
            if d.out_valid.value == 1 and d.out_ready.value == 1:
                self.out.append(int(d.out_data.value))
                if d.out_last.value == 1 and self.last_ns is None:
                    self.last_ns = cocotb.utils.get_sim_time("ns")
                    self.last_seen = True

    async def run_frame(self, mode, w, h, stream):
        d = self.dut
        self.out, self.last_seen = [], False
        self.start_ns = self.last_ns = None
        self.out_stalls = self.pix_gaps = self.drive_cycles = 0
        await self.configure(mode, w, h)
        await self.cfg_write(REG_CMD, 1)
        assert d.status_error.value == 0, "start raised an error: cause %d" % int(
            d.err_cause.value)
        self.start_ns = cocotb.utils.get_sim_time("ns")
        i = 0
        for cyc in range(CAP):
            feeding = i < len(stream)
            if feeding:
                d.pix_valid.value = 1
                d.pix_data.value = stream[i]
            else:
                d.pix_valid.value = 0
            await RisingEdge(d.clk)
            if feeding and d.pix_valid.value != 1:
                self.pix_gaps += 1
            if d.pix_valid.value == 1 and d.pix_ready.value == 1:
                i += 1
            if self.last_seen and i == len(stream):
                self.drive_cycles = cyc + 1
                break
        else:
            raise AssertionError(
                "frame did not finish: sent %d of %d pixel bytes, %d output bytes"
                % (i, len(stream), len(self.out)))
        d.pix_valid.value = 0
        await self.wait_idle()
        self.cycles = int((cocotb.utils.get_sim_time("ns") - self.start_ns) / 10)
        assert d.status_error.value == 0, "frame ended with status_error set"
        return bytes(self.out)

    @property
    def out_last_cycles(self):
        assert self.last_ns is not None, "out_last was never seen"
        return int((self.last_ns - self.start_ns) / 10)


def _write_rows():
    os.makedirs(os.path.dirname(OUT_JSON) or ".", exist_ok=True)
    doc = {
        "schema_version": 1,
        "kind": "frame-cycle-count",
        "issue": 113,
        "note": ("Simulated cycle counts, never measured (spec/codec.md section 9, "
                 "CLAUDE.md). Icarus + cocotb, RTL with sram_macro_model.v, no host "
                 "stalls."),
        "testbench": "verification/rtl/test_top_frame_cycles.py",
        "signoff_clock_hz": CLOCK_HZ,
        "frames_per_s": FRAMES_PER_S,
        "frame_period_cycles": FRAME_PERIOD,
        "record_0005_bound_cycles": RECORD_0005_BOUND,
        "cycle_floor": CYCLE_FLOOR,
        "cycle_ceiling": CYCLE_CEILING,
        "rows": _ROWS,
    }
    with open(OUT_JSON, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=False)
        f.write("\n")


async def frame_cycle_case(dut, name, quality):
    t0 = time.monotonic()
    rgb, _ = load_image(name, W, H)
    host = CycleHost(dut, seed=quality)
    await host.reset()
    q_luma, q_chroma = jpeg_golden.quality_tables(quality)
    await load_quant(host, q_luma, q_chroma)

    pix = [tuple(rgb[3 * i:3 * i + 3]) for i in range(W * H)]
    stream = colour_stream(pix, W, H)
    assert len(stream) == CYCLE_FLOOR, "pixel stream is %d bytes, expected %d" % (
        len(stream), CYCLE_FLOOR)
    got = await host.run_frame(0, W, H, stream)

    cycles = host.out_last_cycles
    want = jpeg_golden.encode(list(rgb), W, H, "colour", q_luma, q_chroma)
    im = decode_jpeg(got)

    row = {
        "image": name,
        "width": W,
        "height": H,
        "mode": "colour",
        "quality": quality,
        "output_bytes": len(got),
        "cycles_to_out_last": cycles,
        "cycles_to_status_idle": host.cycles,
        "fraction_of_frame_period": round(cycles / FRAME_PERIOD, 6),
        "fraction_of_record_0005_bound": round(cycles / RECORD_0005_BOUND, 6),
        "within_floor_ceiling": CYCLE_FLOOR <= cycles <= CYCLE_CEILING,
        "golden_match": got == want,
        "golden_bytes": len(want),
        "decode": {"size": list(im.size), "mode": im.mode},
        "out_ready_stall_cycles": host.out_stalls,
        "pix_valid_gap_cycles": host.pix_gaps,
        "drive_cycles": host.drive_cycles,
        "wall_time_s": round(time.monotonic() - t0, 3),
    }
    _ROWS.append(row)
    _write_rows()
    dut._log.info(
        "colour %s %dx%d q%d: %d bytes, %d cycles to out_last (%.1f%% of the "
        "%d-cycle frame period, %.1f%% of the record 0005 bound), %d cycles to "
        "status_idle (simulated)",
        name, W, H, quality, len(got), cycles,
        100.0 * cycles / FRAME_PERIOD, FRAME_PERIOD,
        100.0 * cycles / RECORD_0005_BOUND, host.cycles)

    # Host-stall freedom is enforced, not assumed.
    assert host.out_stalls == 0, "out_ready was deasserted for %d cycles" % host.out_stalls
    assert host.pix_gaps == 0, "pix_valid was gapped for %d cycles" % host.pix_gaps
    # Decodability is an independent check, never a substitute for byte-exactness.
    assert im.size == (W, H), im.size
    assert im.mode == "RGB", im.mode
    assert got == want, "%d bytes vs golden %d, first difference at index %d" % (
        len(got), len(want), first_diff(got, want))
    # A count outside the mechanical range is a finding to file, not to tune away.
    assert CYCLE_FLOOR <= cycles <= CYCLE_CEILING, (
        "%d cycles to out_last is outside [%d, %d]: file this as a finding, do not "
        "tune it away" % (cycles, CYCLE_FLOOR, CYCLE_CEILING))


@cocotb.test()
async def test_scene_fbm_q50(dut):
    """Typical content at the reset-default quality."""
    await frame_cycle_case(dut, "scene_fbm", 50)


@cocotb.test()
async def test_noise_max_entropy_q50(dut):
    """Worst-case content (spec section 9 names it) at the same quality."""
    await frame_cycle_case(dut, "noise_max_entropy", 50)


@cocotb.test()
async def test_noise_max_entropy_q95(dut):
    """Output-side stress: the largest real output of the ten section 12 images."""
    await frame_cycle_case(dut, "noise_max_entropy", 95)
