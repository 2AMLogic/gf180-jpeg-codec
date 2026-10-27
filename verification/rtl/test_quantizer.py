"""Directed test of the quantizer stage (jc_quant, jc_quant_core), issue #44.

Run (toplevel jc_quant):

    python3 verification/common/run_tb.py --toplevel jc_quant --test-module test_quantizer \
        --test-dir verification/rtl \
        --source jc_quant.v --source jc_quant_core.v

The reference is the spec section 5 expression, written out here and
independent of verification/golden/. The exhaustive sweep over all x and Q is
tb_quantizer_exhaustive.v (run_quantizer_exhaustive.sh); this file checks the
directed cases, the AC clamp, the stage's Q-word handling and cycles per block.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


def ref_q(x, q, ac):
    d = 8 * q
    m = (abs(x) + (d >> 1)) // d
    v = -m if x < 0 else m
    return max(-1023, min(1023, v)) if ac else v


def words(table):
    return [sum(table[4 * w + k] << (8 * k) for k in range(4)) for w in range(16)]


async def start(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.s5_valid.value = 0
    dut.s5_data.value = 0
    dut.s5_tag.value = 0
    dut.s6_ready.value = 1
    dut.qm_valid.value = 0
    dut.qm_rdata.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def serve_q(dut, tables, latency, stats):
    """M1 model: answers each qm_req after `latency` cycles (>= 1)."""
    async def run():
        pending = []   # [cycles still to wait, word]
        while True:
            await RisingEdge(dut.clk)
            if dut.rst_n.value == 0:
                continue
            dut.qm_valid.value = 0
            if dut.qm_req.value == 1:   # request presented in the cycle that just ended
                assert not pending, "second request while one is outstanding"
                stats["reqs"] += 1
                comp, word = int(dut.qm_comp.value), int(dut.qm_word.value)
                pending.append([latency - 1, words(tables[comp])[word]])
            for p in list(pending):
                if p[0] == 0:           # data valid `latency` cycles after the request cycle
                    dut.qm_valid.value = 1
                    dut.qm_rdata.value = p[1]
                    pending.remove(p)
                else:
                    p[0] -= 1
    return cocotb.start_soon(run())


async def run_blocks(dut, blocks, tables, latency=2, ready_pattern=None):
    """blocks: list of (comp, [64 coefs]). Returns outputs and cycles per block."""
    stats = {"reqs": 0}
    serve_q(dut, tables, latency, stats)
    outs, spans = [], []
    done = {"n": 0}

    async def drive():
        for bi, (comp, coefs) in enumerate(blocks):
            t0 = None
            for i, c in enumerate(coefs):
                dut.s5_valid.value = 1
                dut.s5_data.value = c & 0x7FFF
                last = int(bi == len(blocks) - 1 and i == 63)
                dut.s5_tag.value = (last << 2) | comp
                while True:
                    await RisingEdge(dut.clk)
                    if dut.s5_ready.value == 1:
                        break
                if t0 is None:
                    t0 = cocotb.utils.get_sim_time("ns")
            spans.append((t0, cocotb.utils.get_sim_time("ns")))
        dut.s5_valid.value = 0

    drv = cocotb.start_soon(drive())
    total = 64 * len(blocks)
    guard = 0
    while len(outs) < total:
        await RisingEdge(dut.clk)       # values read here are those the DUT sampled
        if dut.s6_valid.value == 1 and dut.s6_ready.value == 1:
            v = int(dut.s6_data.value)
            outs.append((v - 4096 if v >= 2048 else v, int(dut.s6_tag.value)))
        if ready_pattern is not None:
            await FallingEdge(dut.clk)
            dut.s6_ready.value = ready_pattern()
        guard += 1
        assert guard < 200 * total, "stage stalled"
    await drv
    return outs, spans, stats


def flat_table(v):
    return [v] * 64


def check(blocks, tables, outs):
    k = 0
    for bi, (comp, coefs) in enumerate(blocks):
        for i, c in enumerate(coefs):
            q, tag = outs[k]
            exp = ref_q(c, tables[comp][i], i != 0)
            assert q == exp, f"block {bi} pos {i}: x={c} Q={tables[comp][i]} got {q} expected {exp}"
            exp_tag = ((int(bi == len(blocks) - 1 and i == 63)) << 2) | comp
            assert tag == exp_tag, f"block {bi} pos {i}: tag {tag:03b} expected {exp_tag:03b}"
            k += 1


@cocotb.test()
async def test_spec_worked_example(dut):
    """spec 5: x=-3323, Q=16 -> -26; first row of the record 0003 block."""
    await start(dut)
    x = [-3323, -241, -489, 218, 449, -160, -19, 4] + [0] * 56
    qt = [16, 11, 10, 16, 24, 40, 51, 61] + [16] * 56
    outs, _, _ = await run_blocks(dut, [(0, x)], [qt, qt])
    assert [o[0] for o in outs[:8]] == [-26, -3, -6, 2, 2, -1, 0, 0]
    check([(0, x)], [qt, qt], outs)


@cocotb.test()
async def test_ac_clamp_q1(dut):
    """The AC clamp acts at +-1023 for Q=1 near the extreme; DC does not clamp."""
    await start(dut)
    x = [-8192, 8191, -8191, 8188, -8188, 8187, -8187, 8128] + [0] * 56
    tab = flat_table(1)
    outs, _, _ = await run_blocks(dut, [(0, x)], [tab, tab])
    got = [o[0] for o in outs[:8]]
    # position 0 is DC: -8192/8 = -1024 unclamped
    assert got[0] == -1024, got
    assert got[1:5] == [1023, -1023, 1023, -1023], got  # clamp acting
    assert got[5:7] == [1023, -1023], got               # 8187 -> 1023 exactly, no clamp
    assert got[7] == 1016, got
    check([(0, x)], [tab, tab], outs)


@cocotb.test()
async def test_edges(dut):
    """x=0, |x| at the rounding half point (4Q), Q=255, mixed tables."""
    await start(dut)
    rnd = random.Random(44)
    tab0 = [rnd.randint(1, 255) for _ in range(64)]
    tab0[1], tab0[2], tab0[3] = 255, 1, 255
    tab1 = [rnd.randint(1, 255) for _ in range(64)]
    x = [0] * 64
    for i in range(1, 64):
        q = tab0[i]
        x[i] = rnd.choice([0, 4 * q - 1, 4 * q, -(4 * q), -(4 * q - 1), 12 * q, -12 * q, 8191, -8191])
    x[0] = 4 * tab0[0]
    outs, _, _ = await run_blocks(dut, [(0, x), (1, x)], [tab0, tab1])
    check([(0, x), (1, x)], [tab0, tab1], outs)
    assert outs[0][0] == 1  # DC exactly on the half point rounds away from zero


@cocotb.test()
async def test_random_blocks_and_backpressure(dut):
    await start(dut)
    rnd = random.Random(1)
    tables = [[rnd.randint(1, 255) for _ in range(64)] for _ in range(2)]
    blocks = []
    for b in range(12):
        comp = rnd.choice([0, 1, 2])
        coefs = [rnd.randint(-8191, 8191) for _ in range(64)]
        coefs[0] = rnd.randint(-8192, 8128)
        blocks.append((comp, coefs))
    tabs = [tables[0], tables[1], tables[1]]
    outs, _, _ = await run_blocks(dut, blocks, tabs, latency=3,
                                  ready_pattern=lambda: int(rnd.random() < 0.6))
    check(blocks, tabs, outs)


@cocotb.test()
async def test_cycles_per_block(dut):
    """Budget (0005 section 7, stage 3): at most 72 cycles per block at M1
    latency 2, and far below the 231.5 per-block limit of spec 9."""
    await start(dut)
    rnd = random.Random(7)
    tabs = [[rnd.randint(1, 255) for _ in range(64)] for _ in range(2)]
    blocks = [(i % 2, [rnd.randint(-8191, 8191) for _ in range(64)]) for i in range(8)]
    outs, spans, stats = await run_blocks(dut, blocks, tabs, latency=2)
    check(blocks, tabs, outs)
    total = (spans[-1][1] - spans[0][0]) / 10 / len(blocks)
    dut._log.info(f"cycles per block (back-to-back, M1 latency 2): {total:.1f}; Q requests: {stats['reqs']}")
    assert stats["reqs"] == 16 * len(blocks)
    assert total <= 72, total
