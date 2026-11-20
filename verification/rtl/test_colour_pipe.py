"""Section 4 unit tests over the pipelined converter chain (issue #132).

`test_colour.py` proves the combinational composition (`colour_convert`,
jc_cc_mul_a/_b/_c + jc_cc_add + jc_cc_t3a + jc_cc_t3b + jc_cc_t4 + jc_cc_rnd) against `ref_ycc`; this bench
proves the *pipelined* chain `jc_cc_pipe` — the instantiation jc_downsample
actually uses — computes the same values at the pipe latency, from the same
vector classes: the worked examples, the corners, the R=G=B axis, 100,000
random vectors, and the grey byte pass-through. Every value is compared
against `ref_ycc` (and the raw byte for grey), never against the DUT's own
combinational output.

Timing contract (measured, then pinned): an input written in the timestep of
edge E is sampled by the pipe's first stage at the next edge and its bytes
sit in the output registers from the eighth; a read taken when a RisingEdge
coroutine resumes shows the output registers as of the *previous* edge — so
a vector becomes readable exactly eight driver edges after its `send` tick.
The driver tracks that offset explicitly (`LATENCY`) and self-checks it on
every vector: a one-stage misalignment anywhere in jc_cc_pipe fails loudly.

    python3 verification/rtl/run_stage.py colour_pipe
"""

import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from colour_ref import ref_ycc  # the spec section 4 integer reference

# Driver edges from a vector's `send` tick to the edge whose read shows its
# bytes (measured; includes the pre-edge read convention).
LATENCY = 8


class PipeDriver:
    """One vector per clock. Inputs are driven in the timestep of a rising
    edge; the oldest outstanding vector is checked at the edge where the
    LATENCY contract says its bytes are the ones in the output registers."""

    def __init__(self, dut):
        self.dut = dut
        self.pending = []       # ((grey, expected_y), tag, send_edge_index)
        self.edges = 0

    async def reset(self):
        dut = self.dut
        dut.rst_n.value = 0
        dut.en.value = 1   # back-to-back stream: one valid vector per cycle
        dut.grey.value = 0
        dut.r_reg.value = 0
        dut.g_reg.value = 0
        dut.pix.value = 0
        for _ in range(2):
            await self._tick()
        dut.rst_n.value = 1
        await self._tick()

    async def _tick(self):
        await RisingEdge(self.dut.clk)
        self.edges += 1

    def _check(self, grey, exp_y, tag):
        dut = self.dut
        got_y = int(dut.y.value)
        if grey:
            assert got_y == exp_y, f"{tag}: grey Y must pass through: {got_y} != {exp_y}"
            assert int(dut.chroma_valid.value) == 0, f"{tag}: grey chroma_valid must be low"
        else:
            got = (got_y, int(dut.cb.value), int(dut.cr.value))
            assert got == exp_y, f"{tag}: got {got}, want {exp_y}"
            assert int(dut.chroma_valid.value) == 1, f"{tag}: colour chroma_valid must be high"

    def _check_due(self):
        while self.pending and self.pending[0][2] + LATENCY <= self.edges:
            (grey, exp_y), tag, _ = self.pending.pop(0)
            self._check(grey, exp_y, tag)

    async def send(self, grey, r, g, b, exp_y, tag):
        self._check_due()
        dut = self.dut
        dut.grey.value = grey
        # jc_downsample's wiring: the completing beat's byte rides `pix` —
        # the B byte in colour mode, the Y byte itself in grey mode; the
        # latched bytes are stale colour data the select ignores in grey.
        dut.r_reg.value = r
        dut.g_reg.value = g
        dut.pix.value = r if grey else b
        await self._tick()
        self.pending.append(((grey, exp_y), tag, self.edges))

    async def drain(self):
        while self.pending:
            due = self.pending[0][2] + LATENCY
            while self.edges < due:
                await self._tick()
            self._check_due()


@cocotb.test()
async def test_worked_examples(dut):
    """The spec table vectors, at the pipe latency."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    drv = PipeDriver(dut)
    await drv.reset()
    for rgb, want in {
        (255, 0, 0): (76, 85, 255),
        (12, 200, 77): (130, 98, 44),
        (255, 255, 255): (255, 128, 128),
        (0, 0, 0): (0, 128, 128),
    }.items():
        assert ref_ycc(*rgb) == want  # the reference itself matches the spec table
        await drv.send(0, *rgb, want, rgb)
    await drv.drain()


@cocotb.test()
async def test_corners_and_grey_axis(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    drv = PipeDriver(dut)
    await drv.reset()
    for rgb in itertools.product((0, 255), repeat=3):
        await drv.send(0, *rgb, ref_ycc(*rgb), rgb)
    for v in range(256):  # R=G=B gives Cb=Cr=128
        y, cb, cr = ref_ycc(v, v, v)
        assert (cb, cr) == (128, 128), v
        await drv.send(0, v, v, v, (y, cb, cr), ("axis", v))
    await drv.drain()


@cocotb.test()
async def test_random_rgb(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    drv = PipeDriver(dut)
    await drv.reset()
    rng = random.Random(42)
    for _ in range(100_000):
        rgb = (rng.randrange(256), rng.randrange(256), rng.randrange(256))
        await drv.send(0, *rgb, ref_ycc(*rgb), rgb)
    await drv.drain()


@cocotb.test()
async def test_grey_bypass(dut):
    """The grey byte must pass through at the same LATENCY as colour data."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    drv = PipeDriver(dut)
    await drv.reset()
    for v in (0, 1, 127, 128, 254, 255):
        await drv.send(1, v, 77, 200, v, ("grey", v))
    await drv.drain()
