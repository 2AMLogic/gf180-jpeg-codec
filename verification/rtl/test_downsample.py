"""Unit test of the retimed ingest/downsample stage (issue #132).

Run (toplevel tb_downsample_top):

    python3 verification/rtl/run_stage.py downsample

This is the first bench that drives `pix_valid`/`pix_ready` at the
jc_downsample boundary, and it owns the two properties the #132 retime puts
at risk:

* **Value identity.** Every s2 word is compared against a bit-accurate Python
  model of the spec section 4 pipeline (colour conversion from the integer
  reference, 2 x 2 chroma average with the even/odd bias, lane packing,
  offsets, frame_last) — written here, independent of the golden model.
* **No dropped word under the new interlock.** Writes now load ten cycles
  after the pixel's completing beat and the pending stage holds two sets (a
  set = one pixel's Y word alone, or its Y + Cb + Cr together) in a two-slot
  FIFO. The stall scenario below pins `s2_ready` low across the first chroma
  sets so two pixels' writes are committed while the older set still waits —
  the exact case the pre-retiming single-set interlock could not cover — and
  the drained word stream must still equal the model exactly, order
  included. The in-flight occupancy is read from the DUT (`dut.dut.nset` /
  `dut.dut.inflight`) so the scenario is asserted exercised, not assumed.

Grey mode rides the same latency; its byte pass-through and the frame_last
of the final word are checked against the same model.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from colour_ref import ref_ycc  # the spec section 4 integer reference

# jc_downsample's inserted latency: a pixel accepted during cycle T has its
# writes in the pending slots ten cycles later (load edge at the end of
# T+10), visible from T+11. The bench anchors the first-word check to the
# cycle the DUT itself reports for the first lane-3 pixel's completing beat,
# so the assertion pins the latency, not the feeder's write timing.
FIRST_WORD_LATENCY = 11  # completing beat of a lane-3 pixel -> its word visible


def make_pixels(grey, mcus):
    """Deterministic pseudo-image: the pixel values and the byte stream."""
    n = 8 if grey else 16
    stream, pixels = [], []
    for _ in range(mcus):
        for py in range(n):
            for px in range(n):
                if grey:
                    v = (17 * px + 29 * py + 3) & 0xFF
                    stream.append(v)
                    pixels.append((px, py, v, None, None))
                else:
                    rgb = ((3 * px + 5 * py) & 0xFF,
                           (7 * px + 11 * py + 1) & 0xFF,
                           (13 * px + 2 * py + 2) & 0xFF)
                    stream.extend(rgb)
                    pixels.append((px, py) + rgb)
    return stream, pixels


def model_words(grey, mcu_cols, mcu_rows, pixels):
    """The flat drain-order s2 word stream the DUT must produce."""
    words = []
    yw = cbw = crw = 0
    pcb = pcr = 0
    acc_cb = [0] * 8
    acc_cr = [0] * 8
    per_mcu = 64 if grey else 256
    last_mcu = mcu_cols * mcu_rows - 1
    for i, (px, py, r, g, b) in enumerate(pixels):
        mcu, _ = divmod(i, per_mcu)
        mcu_c, mcu_r = mcu % mcu_cols, mcu // mcu_cols
        last_mcu_here = mcu == last_mcu
        n = 8 if grey else 16
        frm_end = last_mcu_here and px == n - 1 and py == n - 1
        y, cb, cr = (r, None, None) if grey else ref_ycc(r, g, b)
        lane = px & 3
        set_words = []
        if lane == 3:
            y_word = (y << 24) | (yw & 0xFFFFFF)
            if grey:
                y_off = ((py & 7) << 1) + ((px >> 2) & 1)
            else:
                y_off = ((((py >> 3) & 1) << 5) + (((px >> 3) & 1) << 4)
                         + ((py & 7) << 1) + ((px >> 2) & 1))
            set_words.append((grey and frm_end, y_off, y_word))
        if not grey:
            cx = px >> 1
            if px % 2 == 0:
                pcb, pcr = cb, cr
            else:
                hs_cb = pcb + cb
                hs_cr = pcr + cr
                bias = 2 if (cx & 1) else 1
                if py % 2 == 0:
                    acc_cb[cx] = hs_cb
                    acc_cr[cx] = hs_cr
                else:
                    o_cb = ((hs_cb + acc_cb[cx] + bias) >> 2) & 0xFF
                    o_cr = ((hs_cr + acc_cr[cx] + bias) >> 2) & 0xFF
                    clane = cx & 3
                    if clane == 0:
                        cbw = (cbw & ~0xFF) | o_cb
                        crw = (crw & ~0xFF) | o_cr
                    elif clane == 1:
                        cbw = (cbw & ~(0xFF << 8)) | (o_cb << 8)
                        crw = (crw & ~(0xFF << 8)) | (o_cr << 8)
                    elif clane == 2:
                        cbw = (cbw & ~(0xFF << 16)) | (o_cb << 16)
                        crw = (crw & ~(0xFF << 16)) | (o_cr << 16)
                    else:
                        coff = (((py >> 1) & 7) << 1) + ((px >> 3) & 1)
                        set_words.append((False, 64 + coff, (o_cb << 24) | cbw))
                        set_words.append((frm_end, 80 + coff, (o_cr << 24) | crw))
        if lane != 3:
            shift = lane * 8
            yw = (yw & ~(0xFF << shift)) | (y << shift)
        words.extend(set_words)
    return words


async def reset(dut):
    dut.frame_active.value = 0
    dut.mode.value = 0
    dut.pix_valid.value = 0
    dut.pix_data.value = 0
    dut.s2_ready.value = 0
    dut.rst_n.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def run_frame(dut, grey, mcu_cols, mcu_rows, stream, expected_words,
                    ready_fn, max_cycles=400_000):
    """Drives the stream with pix_valid held, samples every s2 transfer in
    drain order; returns (words, first_word_cycle, pix_stalls, beats,
    max_inflight).

    Conventions, matching the house benches: pixel bytes are driven before
    the sampling edge and the post-edge `pix_valid && pix_ready` read decides
    acceptance; an s2 word is read during the cycle it is stable, before its
    drain edge. `max_inflight` tracks `nset + inflight` so a stall scenario
    can prove two sets were genuinely in flight.
    """
    dut.mode.value = 1 if grey else 0
    dut.mcu_cols.value = mcu_cols
    dut.mcu_rows.value = mcu_rows
    # mode is static while a frame is active and is registered once here
    # (grey_q): settle it before raising frame_active, as the cfg-host
    # register writes do at the top level
    await RisingEdge(dut.clk)
    dut.frame_active.value = 1

    words = []
    first_word_cycle = None
    first_emit_cycle = None
    stalls = 0
    beats = 0
    max_inflight = 0
    i = 0
    cycle = 0
    while cycle < max_cycles:
        # sample this cycle's drain with the s2_ready value currently in
        # effect on the wire (written last timestep), before updating it
        if int(dut.s2_valid.value) == 1 and int(dut.s2_ready.value) == 1:
            raw = int(dut.s2_data.value)
            words.append(((raw >> 39) & 1, (raw >> 32) & 0x7F, raw & 0xFFFFFFFF))
            if first_word_cycle is None:
                first_word_cycle = cycle
        dut.s2_ready.value = 1 if ready_fn(cycle) else 0
        if (first_emit_cycle is None and int(dut.dut.pix_done.value) == 1
                and int(dut.dut.px.value) == 3):
            first_emit_cycle = cycle
        infl = int(dut.dut.nset.value) + int(dut.dut.inflight.value)
        max_inflight = max(max_inflight, infl)
        if i < len(stream):
            dut.pix_valid.value = 1
            dut.pix_data.value = stream[i]
        else:
            dut.pix_valid.value = 0
        await RisingEdge(dut.clk)
        cycle += 1
        if int(dut.pix_valid.value) == 1 and int(dut.pix_ready.value) == 1:
            beats += 1
            i += 1
        elif i < len(stream):
            stalls += 1
        if i >= len(stream) and len(words) >= expected_words:
            break
    dut.frame_active.value = 0
    dut.pix_valid.value = 0
    assert i >= len(stream), (
        "frame did not consume its stream: %d of %d bytes accepted in %d cycles"
        % (i, len(stream), cycle))
    assert len(words) >= expected_words, (
        "frame produced %d of %d words in %d cycles" % (len(words), expected_words, cycle))
    return words, first_word_cycle, first_emit_cycle, stalls, beats, max_inflight


async def check_frame(dut, grey, mcu_cols, mcu_rows, ready_fn, expect_stalls=None,
                      check_latency=True):
    stream, pixels = make_pixels(grey, mcu_cols * mcu_rows)
    want = model_words(grey, mcu_cols, mcu_rows, pixels)
    (words, first_word_cycle, first_emit_cycle, stalls, beats,
     max_inflight) = await run_frame(
        dut, grey, mcu_cols, mcu_rows, stream, len(want), ready_fn)
    assert words == want, (
        "word stream mismatch: %d words, first difference at %d"
        % (len(words), next(j for j in range(max(len(words), len(want)))
                            if j >= len(words) or j >= len(want)
                            or words[j] != want[j])))
    assert first_emit_cycle is not None, "the DUT never completed a lane-3 pixel"
    if not check_latency:
        return
    assert first_word_cycle == first_emit_cycle + FIRST_WORD_LATENCY, (
        "first s2 word during cycle %d, expected %d (first lane-3 beat at %d + %d)"
        % (first_word_cycle, first_emit_cycle + FIRST_WORD_LATENCY,
           first_emit_cycle, FIRST_WORD_LATENCY))
    if expect_stalls is not None:
        assert stalls == expect_stalls, (
            "pix stalls %d, expected %d" % (stalls, expect_stalls))
    return beats, stalls, max_inflight


@cocotb.test()
async def test_colour_frame_no_stall(dut):
    """One pixel per 3 beats, zero input stalls, and the exact word stream."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    beats, stalls, _ = await check_frame(
        dut, False, 2, 1, lambda c: True, expect_stalls=0)
    assert beats == 2 * 768, "accepted %d beats, expected 1536" % beats


@cocotb.test()
async def test_colour_frame_stall_two_sets_in_flight(dut):
    """s2 pinned low across the first chroma sets: two pixels' writes in
    flight at once, nothing dropped, order preserved."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    def ready(c):
        return not (60 <= c < 160)  # covers the first sets' commit/load window

    beats, stalls, max_inflight = await check_frame(dut, False, 2, 1, ready)
    assert max_inflight >= 2, (
        "scenario never had two sets in flight (max occupancy %d)" % max_inflight)


@cocotb.test()
async def test_colour_frame_random_ready(dut):
    """Pseudo-random s2_ready with a fixed seed; the stream must still be
    bit-identical to the model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    rng = random.Random(42)

    def ready(c):
        return rng.random() < 0.7

    # the randomized pattern's absolute cycle alignment depends on the
    # simulator's write/read scheduling; the deterministic tests pin the
    # latency, this one pins ordering and no-drop under random drains
    await check_frame(dut, False, 2, 1, ready, check_latency=False)


@cocotb.test()
async def test_grey_block(dut):
    """Grey 8 x 8: byte pass-through at the same latency, 16 words, the last
    word carrying frame_last. (The two-set interlock backpressures grey
    slightly — lane-3 sets arrive every 4 beats while the load latency is 10 —
    which the spec's grey budget absorbs; the colour rows in
    test_top_frame_cycles carry the no-added-stall guarantee, and colour
    acceptance is unaffected: its sets arrive every 12 beats.)"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await check_frame(dut, True, 1, 1, lambda c: True)
