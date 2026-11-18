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
  `pix_valid` is held at 1 until the last pixel byte is accepted. The holds
  are structural (drive code); what is *observed* is the DUT side:
  `pix_valid && !pix_ready` (input backpressure the DUT imposed on a host
  that never stalls) and `out_valid && !out_ready`.
* Where the cycles go (issue #119): one sampler coroutine classifies, per
  clock edge of the frame window, every stage-boundary handshake as stalled
  (`valid && !ready`), starved (`!valid && ready`), transferred
  (`valid && ready`) or idle, plus the `m0_en` / `m1_en` / `m2_en` port
  occupancy and the arbitration-request stalls (`hf_m1_req && !hf_m1_gnt`,
  `hf_m2_req && !hf_m2_gnt`, `qa_pend && !qa_gnt`). The window is frame
  start to the `out_last` beat, inclusive, so each boundary's four buckets
  sum to exactly the sampled edge count. That count is the true
  integer-cycle figure between the two edges; `cycles_to_out_last` is the
  same interval in integer picoseconds (issue #208: the earlier float-ns
  quotient floored one cycle low on rows carrying accumulated
  sub-picosecond clock drift, so the count shifted with the test's
  position in the simulation), and the bench asserts the two agree on
  every row.
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

    python3 verification/rtl/run_stage.py top_golden --test-module test_top_frame_cycles

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
from collections import deque

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
from cfg_host import REG_CMD  # noqa: E402
from test_top_smoke import (  # noqa: E402
    Host, CAP, colour_stream, decode_jpeg,
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

# Stage boundaries: valid/ready handshake pairs on top-level wires of
# `jpeg_codec_top`, so cocotb hierarchical reads count them with no RTL
# change. Producer -> consumer, named after decision record 0005 section 7's
# stage rows.
BOUNDARIES = {
    "pix": ("pix_valid", "pix_ready"),   # host -> jc_downsample
    "s2": ("s2_valid", "s2_ready"),      # jc_downsample -> jc_mb_ctrl
    "s3": ("s3_valid", "s3_ready"),      # jc_mb_ctrl -> jc_dct
    "s4": ("s4_valid", "s4_ready"),      # jc_dct -> jc_zigzag
    "s5": ("s5_valid", "s5_ready"),      # jc_zigzag -> jc_quant
    "s6": ("s6_valid", "s6_ready"),      # jc_quant -> jc_huff
    "s7": ("s7_valid", "s7_ready"),      # jc_huff -> jc_bitpack
    "bp": ("bp_valid", "bp_ready"),      # jc_bitpack -> jc_out_mux
    "out": ("out_valid", "out_ready"),   # jc_out_mux -> host
}

# The record 0005 section 7 memory rows: SRAM port enable occupancy, and
# arbitration-request stalls. `hf_m1` (jc_huff) and `qa` (the quantizer's
# request holder) share M1 through `u_arb1`, so `hf_m1` stalls separate
# arbitration contention from jc_huff's own FSM cost.
SRAM_PORTS = ("m0_en", "m1_en", "m2_en")
ARB_PAIRS = {
    "hf_m1": ("hf_m1_req", "hf_m1_gnt"),
    "hf_m2": ("hf_m2_req", "hf_m2_gnt"),
    "qa": ("qa_pend", "qa_gnt"),
}


def _bit(sig):
    """0/1 of a one-bit signal; X/Z reads as 0 (must not occur in-window)."""
    try:
        return int(sig.value)
    except ValueError:
        return 0


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
    (this bench is the no-stall case by definition), the `out_last`
    timestamp kept, and one `stage_sampler` coroutine added alongside: it
    counts the per-boundary stalled/starved/transferred/idle cycles of
    issue #119 over exactly the `cycles_to_out_last` window.
    `in_gap` / `out_gap` are pinned at 0.
    """

    def __init__(self, dut, seed=1):
        super().__init__(dut, in_gap=0.0, out_gap=0.0, seed=seed)
        self.drive_cycles = 0
        self.start_ps = None
        self.beat_ps = None
        self.stage_counts = None
        self.sram_occupancy = None
        self.arb_stalls = None
        self.stage_sample_cycles = None
        self.sampler_stop = False
        self.sampler_deadline_ps = None

    async def out_monitor(self):
        """Hold `out_ready` high for the whole run and timestamp `out_last`."""
        d = self.dut
        while True:
            d.out_ready.value = 1
            await RisingEdge(d.clk)
            if d.out_valid.value == 1 and d.out_ready.value == 1:
                self.out.append(int(d.out_data.value))
                if d.out_last.value == 1 and self.beat_ps is None:
                    self.last_seen = True
                    # Integer-ps stamp of the `out_last` beat: it derives
                    # `cycles_to_out_last` (issue #208) and arms the
                    # sampler's backstop deadline a fraction of one
                    # clock period past the beat. The sampler's primary stop
                    # is its own `out_last` handshake check, so this deadline
                    # only has to let the sampler, resuming on the same
                    # simulation step as this monitor, still sample the beat
                    # edge: the deadline test is strict and the next real
                    # edge is a full period away, so any margin shorter than
                    # one period is the same program. Integer ps, so no
                    # float rounding can bite.
                    self.beat_ps = cocotb.utils.get_sim_time()
                    self.sampler_deadline_ps = self.beat_ps + 3000

    async def stage_sampler(self):
        """Classify every boundary handshake once per clock of the frame.

        The window starts at the first edge after `run_frame` captures
        `start_ps`. Reads use the same convention as `out_monitor` (the
        values stable in the cycle that ends at each edge), so a boundary's
        four buckets sum to the window length and `out.transferred` equals
        the output byte count.

        The stop is deterministic, not racy. This coroutine's primary stop
        is its own `out_last` handshake check at the bottom of the loop,
        which breaks on the beat edge itself; the deadline `out_monitor`
        arms a fraction of one clock period past the beat is only a
        backstop. The deadline test is strict, so that margin admits no
        extra edges: it exists so that the sampler, resuming on the same
        simulation step as `out_monitor`, still samples the beat edge.
        `run_frame` then calls
        `trim_stage_window`, which pops every sampled edge after the
        beat's edge - the same edge that defined `cycles_to_out_last` - so
        the window is exactly the frame-start-to-`out_last` edge count.
        (`cycles_to_out_last` is the same integer-ps interval since
        issue #208, so the two counts must agree on every row.)

        Two artifacts of a long cocotb session are filtered explicitly,
        both invisible to the DUT (whose cycle counts stay exact):
        each test's `reset()` starts another `Clock` driver, and a
        no-change clock post can re-fire `RisingEdge` without the DUT
        seeing a transition; and the fork-time edge can fire on the step
        `start_ps` was captured. Real clock edges are ~10 ns apart, so any
        fire less than 9.5 ns after the last counted edge - or at or
        before `start_ps` - is skipped and tallied in the row as
        `stage_phantom_edges_skipped`. All times are integer picoseconds.
        """
        d = self.dut
        counts = {n: {"stalled": 0, "starved": 0, "transferred": 0, "idle": 0}
                  for n in BOUNDARIES}
        sram = {p: 0 for p in SRAM_PORTS}
        arb = {a: 0 for a in ARB_PAIRS}
        hist = deque(maxlen=8)
        self.stage_counts = counts
        self.sram_occupancy = sram
        self.arb_stalls = arb
        self._edge_hist = hist
        self.stage_sample_cycles = 0
        self._phantom = 0
        self.sampler_first_ps = None
        prev_ps = None
        while True:
            await RisingEdge(d.clk)
            now = cocotb.utils.get_sim_time()
            if now <= self.start_ps:
                # Fork-time edge: start_soon runs this body in the same step
                # `run_frame` captured start_ps, and the edge registered there
                # can fire on that same step. It is not a frame cycle.
                continue
            if prev_ps is not None and now - prev_ps < 9_500:
                # A real clock edge is ~10 ns after the last one; a re-fire
                # inside a period is a no-change-post artifact the DUT does
                # not see a transition on.
                self._phantom += 1
                continue
            if self.sampler_stop or (
                    self.sampler_deadline_ps is not None
                    and now > self.sampler_deadline_ps):
                break
            prev_ps = now
            if self.sampler_first_ps is None:
                self.sampler_first_ps = now
            self.stage_sample_cycles += 1
            codes = {}
            for name, (v, r) in BOUNDARIES.items():
                valid, ready = _bit(getattr(d, v)), _bit(getattr(d, r))
                bucket = ("transferred" if valid and ready else
                          "stalled" if valid else
                          "starved" if ready else "idle")
                counts[name][bucket] += 1
                codes[name] = bucket
            sram_set = tuple(p for p in SRAM_PORTS if _bit(getattr(d, p)))
            for p in sram_set:
                sram[p] += 1
            arb_set = tuple(a for a, (req, gnt) in ARB_PAIRS.items()
                            if _bit(getattr(d, req)) and not _bit(getattr(d, gnt)))
            for a in arb_set:
                arb[a] += 1
            hist.append((now, codes, sram_set, arb_set))
            if (_bit(d.out_valid) and _bit(d.out_ready) and _bit(d.out_last)):
                break

    def trim_stage_window(self, beat_ps):
        """Pop sampled edges later than the `out_last` beat (see sampler)."""
        while self._edge_hist and self._edge_hist[-1][0] > beat_ps:
            _, codes, sram_set, arb_set = self._edge_hist.pop()
            for name, bucket in codes.items():
                self.stage_counts[name][bucket] -= 1
            for p in sram_set:
                self.sram_occupancy[p] -= 1
            for a in arb_set:
                self.arb_stalls[a] -= 1
            self.stage_sample_cycles -= 1
        assert self._edge_hist and self._edge_hist[-1][0] == beat_ps, (
            "sampler window ends at %s, out_last beat is at %s"
            % (self._edge_hist[-1][0] if self._edge_hist else None, beat_ps))

    async def run_frame(self, mode, w, h, stream):
        d = self.dut
        self.out, self.last_seen = [], False
        self.drive_cycles = 0
        self.sampler_stop = False
        self.beat_ps = None
        self.sampler_deadline_ps = None
        await self.configure(mode, w, h)
        await self.cfg_write(REG_CMD, 1)
        assert d.status_error.value == 0, "start raised an error: cause %d" % int(
            d.err_cause.value)
        self.start_ps = cocotb.utils.get_sim_time()
        cocotb.start_soon(self.stage_sampler())
        try:
            i = 0
            for cyc in range(CAP):
                feeding = i < len(stream)
                if feeding:
                    d.pix_valid.value = 1
                    d.pix_data.value = stream[i]
                else:
                    d.pix_valid.value = 0
                await RisingEdge(d.clk)
                if d.pix_valid.value == 1 and d.pix_ready.value == 1:
                    i += 1
                if self.last_seen and i == len(stream):
                    self.drive_cycles = cyc + 1
                    break
            else:
                raise AssertionError(
                    "frame did not finish: sent %d of %d pixel bytes, %d output bytes"
                    % (i, len(stream), len(self.out)))
        finally:
            self.sampler_stop = True
        d.pix_valid.value = 0
        await self.wait_idle()
        self.cycles = (cocotb.utils.get_sim_time() - self.start_ps) // 10_000
        assert d.status_error.value == 0, "frame ended with status_error set"
        return bytes(self.out)

    @property
    def out_last_cycles(self):
        assert self.beat_ps is not None, "out_last was never seen"
        return (self.beat_ps - self.start_ps) // 10_000


def _write_rows():
    os.makedirs(os.path.dirname(OUT_JSON) or ".", exist_ok=True)
    doc = {
        "schema_version": 2,
        "kind": "frame-cycle-count",
        "issue": 119,
        "note": ("Simulated cycle counts, never measured (spec/codec.md section 9, "
                 "CLAUDE.md). Icarus + cocotb, RTL with sram_macro_model.v, no host "
                 "stalls. schema_version 2 adds the issue #119 per-boundary "
                 "stage counters."),
        "testbench": "verification/rtl/test_top_frame_cycles.py",
        "stage_boundaries": {
            "pix": "host -> jc_downsample",
            "s2": "jc_downsample -> jc_mb_ctrl",
            "s3": "jc_mb_ctrl -> jc_dct",
            "s4": "jc_dct -> jc_zigzag",
            "s5": "jc_zigzag -> jc_quant",
            "s6": "jc_quant -> jc_huff",
            "s7": "jc_huff -> jc_bitpack",
            "bp": "jc_bitpack -> jc_out_mux",
            "out": "jc_out_mux -> host",
        },
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
    host.trim_stage_window(host.beat_ps)
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
        "pix_valid_not_ready_cycles": host.stage_counts["pix"]["stalled"],
        "out_valid_not_ready_cycles": host.stage_counts["out"]["stalled"],
        "stage_counts": host.stage_counts,
        "sram_occupancy_cycles": host.sram_occupancy,
        "arb_stall_cycles": host.arb_stalls,
        "stage_sample_cycles": host.stage_sample_cycles,
        "stage_sample_window_ns": [host.sampler_first_ps / 1000,
                                   host._edge_hist[-1][0] / 1000],
        "stage_phantom_edges_skipped": host._phantom,
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

    # The no-stall hold is structural (out_ready driven 1 on every cycle), so
    # the DUT-side observation below cannot be nonzero unless the bench broke
    # its own guarantee. `pix_valid && !pix_ready` is a real DUT observation
    # (input backpressure) and is recorded, never asserted.
    assert host.stage_counts["out"]["stalled"] == 0, (
        "out_valid was not accepted for %d cycles" % host.stage_counts["out"]["stalled"])
    # The sampler must have covered exactly the frame window: the true
    # integer cycle count between the frame-start edge and the out_last
    # edge. `cycles_to_out_last` is the same integer-ps interval (issue
    # #208 replaced the float-ns quotient, which floored one cycle low on
    # rows carrying accumulated sub-ps clock drift and so shifted with the
    # test's position in the simulation), so all three counts must agree
    # on every row; a regression to float-ns arithmetic shows up as a
    # one-cycle disagreement on a non-first row.
    true_cycles = (host.beat_ps - host.start_ps) // 10_000
    assert host.stage_sample_cycles == true_cycles, (
        "sampler window %d != integer cycle count %d"
        % (host.stage_sample_cycles, true_cycles))
    assert cycles == host.stage_sample_cycles, (
        "cycles_to_out_last %d != sampler window %d (position-dependent count?)"
        % (cycles, host.stage_sample_cycles))
    assert host.stage_counts["pix"]["transferred"] == len(stream), (
        "pix transferred %d != stream %d"
        % (host.stage_counts["pix"]["transferred"], len(stream)))
    assert host.stage_counts["out"]["transferred"] == len(got), (
        "out transferred %d != output bytes %d"
        % (host.stage_counts["out"]["transferred"], len(got)))
    for name, c in host.stage_counts.items():
        assert sum(c.values()) == host.stage_sample_cycles, (
            "boundary %s buckets %d != window %d"
            % (name, sum(c.values()), host.stage_sample_cycles))
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
