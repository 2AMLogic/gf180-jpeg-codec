"""Unit test of the DCT stage (jc_dct, jc_dct1d, jc_xpose_rf), issue #43.

Run (toplevel jc_dct):

    python3 verification/common/run_tb.py --toplevel jc_dct --test-module test_dct \
        --test-dir verification/rtl \
        --source jc_dct.v --source jc_dct1d.v --source jc_xpose_rf.v

The reference below is transcribed from decision record 0003 and is
independent of verification/golden/. Every node asserts that it fits the
0003 word length. Comparison against the golden model is item 5 (#34).
"""

import random
import re
import shutil
import subprocess
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

RTL = Path(__file__).resolve().parent.parent.parent / "rtl"

# ---------------------------------------------------------------- reference

C = dict(
    F0298=2446, F0390=3196, F0541=4433, F0765=6270, F0899=7373, F1175=9633,
    F1501=12299, F1847=15137, F1961=16069, F2053=16819, F2562=20995, F3072=25172,
)
CONST_BITS, PASS1_BITS = 13, 2


def fix(x):
    return int(x * (1 << CONST_BITS) + 0.5)


def test_constants_match_record():
    # 0003 table, FIX(x) = floor(x * 2^13 + 0.5)
    assert fix(0.298631336) == C["F0298"] and fix(0.390180644) == C["F0390"]
    assert fix(0.541196100) == C["F0541"] and fix(0.765366865) == C["F0765"]
    assert fix(0.899976223) == C["F0899"] and fix(1.175875602) == C["F1175"]
    assert fix(1.501321110) == C["F1501"] and fix(1.847759065) == C["F1847"]
    assert fix(1.961570560) == C["F1961"] and fix(2.053119869) == C["F2053"]
    assert fix(2.562915447) == C["F2562"] and fix(3.072711026) == C["F3072"]


def chk(v, bits, what):
    assert -(1 << (bits - 1)) <= v < (1 << (bits - 1)), f"{what}={v} exceeds {bits} bits"
    return v


def descale(x, n):
    return (x + (1 << (n - 1))) >> n


def ref_1d(d, p):
    w = 25 if p == 1 else 30
    S = CONST_BITS - PASS1_BITS if p == 1 else CONST_BITS + PASS1_BITS
    n = lambda v, name: chk(v, w, name)
    t0 = n(d[0] + d[7], "t0"); t7 = n(d[0] - d[7], "t7")
    t1 = n(d[1] + d[6], "t1"); t6 = n(d[1] - d[6], "t6")
    t2 = n(d[2] + d[5], "t2"); t5 = n(d[2] - d[5], "t5")
    t3 = n(d[3] + d[4], "t3"); t4 = n(d[3] - d[4], "t4")
    t10 = n(t0 + t3, "t10"); t13 = n(t0 - t3, "t13")
    t11 = n(t1 + t2, "t11"); t12 = n(t1 - t2, "t12")
    o = [0] * 8
    if p == 1:
        o[0] = n((t10 + t11) << 2, "o0pre"); o[4] = n((t10 - t11) << 2, "o4pre")
    else:
        o[0] = descale(n(t10 + t11, "s0"), 2); o[4] = descale(n(t10 - t11, "s4"), 2)
    z1 = n((t12 + t13) * C["F0541"], "z1e")
    o[2] = descale(n(z1 + n(t13 * C["F0765"], "m"), "x2"), S)
    o[6] = descale(n(z1 + n(t12 * -C["F1847"], "m"), "x6"), S)
    z1 = n(t4 + t7, "z1"); z2 = n(t5 + t6, "z2")
    z3 = n(t4 + t6, "z3"); z4 = n(t5 + t7, "z4")
    z5 = n((z3 + z4) * C["F1175"], "z5")
    t4 = n(t4 * C["F0298"], "p4"); t5 = n(t5 * C["F2053"], "p5")
    t6 = n(t6 * C["F3072"], "p6"); t7 = n(t7 * C["F1501"], "p7")
    z1 = n(z1 * -C["F0899"], "pz1"); z2 = n(z2 * -C["F2562"], "pz2")
    z3 = n(z3 * -C["F1961"], "pz3"); z4 = n(z4 * -C["F0390"], "pz4")
    z3 = n(z3 + z5, "z3f"); z4 = n(z4 + z5, "z4f")
    o[7] = descale(n(t4 + z1 + z3, "x7"), S)
    o[5] = descale(n(t5 + z2 + z4, "x5"), S)
    o[3] = descale(n(t6 + z2 + z3, "x3"), S)
    o[1] = descale(n(t7 + z1 + z4, "x1"), S)
    return o


def ref_block(samples):
    """64 samples (row-major) -> (64 coefficients row-major, pass-1 rows)."""
    d = [s - 128 for s in samples]
    for v in d:
        chk(v, 8, "input")
    rows = [ref_1d(d[8 * r: 8 * r + 8], 1) for r in range(8)]
    for row in rows:
        for v in row:
            chk(v, 14, "pass1 out")
    out = [0] * 64
    for c in range(8):
        col = ref_1d([rows[r][c] for r in range(8)], 2)
        for r in range(8):
            out[8 * r + c] = chk(col[r], 15, "pass2 out")
    return out, rows


T81 = [
    52, 55, 61, 66, 70, 61, 64, 73,
    63, 59, 55, 90, 109, 85, 69, 72,
    62, 59, 68, 113, 144, 104, 66, 73,
    63, 58, 71, 122, 154, 106, 70, 69,
    67, 61, 68, 104, 126, 88, 68, 70,
    79, 65, 60, 70, 77, 68, 58, 75,
    85, 71, 64, 59, 55, 61, 65, 83,
    87, 79, 69, 68, 65, 76, 78, 94,
]
ROW0 = [-2088, -163, -64, -76, 80, -35, -8, 27]
T81_ROWS01 = [-3323, -241, -489, 218, 449, -160, -19, 4,
              36, -174, -486, 82, 105, -57, -68, 39]


def test_reference_worked_examples():
    """0003 worked examples hold for the reference itself."""
    assert ref_1d([s - 128 for s in T81[:8]], 1) == ROW0
    out, _ = ref_block(T81)
    assert out[:16] == T81_ROWS01
    out, _ = ref_block([255] * 64)
    assert out[0] == 8128 and not any(out[1:])
    out, _ = ref_block([0] * 64)
    assert out[0] == -8192 and not any(out[1:])


# ---------------------------------------------------------------- bench

def s14(v):
    return v - (1 << 14) if v & (1 << 13) else v


def s15(v):
    return v - (1 << 15) if v & (1 << 14) else v


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.s3_valid.value = 0
    dut.s3_data.value = 0
    dut.s3_tag.value = 0
    dut.s4_ready.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst_n.value = 1


def block_words(samples, comp, last):
    words = []
    for r in range(8):
        for h in range(2):
            w = 0
            for k in range(4):
                w |= samples[8 * r + 4 * h + k] << (8 * k)
            idx = 2 * r + h
            tag = (int(last and idx == 15) << 3) | (comp << 1) | int(idx == 0)
            words.append((w, tag))
    return words


async def run_blocks(dut, blocks, rng, p_in=1.0, p_out=1.0, timeout=None):
    """Drive blocks [(samples, comp, last)] through S3 and collect S4.

    Everything happens at falling edges; a transfer is a falling-edge cycle in
    which valid and ready are both high (it commits at the next rising edge).
    Returns (outputs, first_accept_cycle, last_s4_cycle) where outputs is a
    list of (idx, coef, comp, last).
    """
    words = [w for b in blocks for w in block_words(*b)]
    want = 64 * len(blocks)
    timeout = timeout or (len(blocks) * 400 + 1000)
    out, wi, cyc, first, lastc = [], 0, 0, None, None
    while len(out) < want:
        await FallingEdge(dut.clk)
        cyc += 1
        assert cyc < timeout, f"timeout: {len(out)}/{want} outputs, {wi}/{len(words)} words in"
        drive = wi < len(words) and rng.random() < p_in
        dut.s3_valid.value = int(drive)
        if drive:
            dut.s3_data.value, dut.s3_tag.value = words[wi]
        dut.s4_ready.value = int(rng.random() < p_out)
        await cocotb.triggers.Timer(1, unit="ns")
        if drive and int(dut.s3_ready.value):
            if first is None:
                first = cyc
            wi += 1
        if int(dut.s4_valid.value) and int(dut.s4_ready.value):
            d = int(dut.s4_data.value)
            t = int(dut.s4_tag.value)
            out.append((d >> 15, s15(d & 0x7FFF), t & 3, t >> 2))
            lastc = cyc
    await FallingEdge(dut.clk)    # let the last beat commit at the rising edge
    dut.s3_valid.value = 0
    dut.s4_ready.value = 0
    return out, first, lastc


def check_outputs(blocks, out):
    for bi, (samples, comp, last) in enumerate(blocks):
        exp, _ = ref_block(samples)
        got = out[64 * bi: 64 * bi + 64]
        order = [8 * r + c for c in range(8) for r in range(8)]
        for k, (idx, coef, ocomp, olast) in enumerate(got):
            assert idx == order[k], f"block {bi} beat {k}: idx {idx} want {order[k]}"
            assert coef == exp[idx], f"block {bi} idx {idx}: coef {coef} want {exp[idx]}"
            assert ocomp == comp, f"block {bi} idx {idx}: comp {ocomp} want {comp}"
            assert olast == int(last and k == 63), f"block {bi} beat {k}: last {olast}"


def spaced(rng, n):
    return [(rng.randrange(256) if i % 2 else rng.choice((0, 255))) for i in range(n)]


@cocotb.test()
async def test_worked_examples(dut):
    """T.81 block (0003 and codec.md section 5 DCT rows), flat 255, flat 0, and
    the 0003 row example read back from the transpose file."""
    test_constants_match_record()
    test_reference_worked_examples()
    await setup(dut)
    rng = random.Random(1)
    t81 = T81[:]
    blocks = [(t81, 0, False), ([255] * 64, 1, False), ([0] * 64, 2, True)]
    out, _, _ = await run_blocks(dut, blocks, rng)
    check_outputs(blocks, out)
    by_idx = {i: c for i, c, _, _ in out[:64]}
    assert [by_idx[i] for i in range(16)] == T81_ROWS01
    flat255 = {i: c for i, c, _, _ in out[64:128]}
    flat0 = {i: c for i, c, _, _ in out[128:192]}
    assert flat255[0] == 8128 and not any(flat255[i] for i in range(1, 64))
    assert flat0[0] == -8192 and not any(flat0[i] for i in range(1, 64))
    # Pass-1 row of the 0003 example: the file still holds the last block (all 0),
    # so run a block whose row 0 is the example row and read row 0 back.
    blk = T81[:]
    out, _, _ = await run_blocks(dut, [(blk, 0, False)], rng)
    row0 = [s14(int(dut.u_rf.mem[c].value)) for c in range(8)]
    assert row0 == ROW0, f"pass-1 row 0 {row0} want {ROW0}"
    dut._log.info("worked examples match: row %s, block rows %s", ROW0, T81_ROWS01)


@cocotb.test()
async def test_directed_blocks(dut):
    await setup(dut)
    rng = random.Random(2)
    blocks = [([0] * 64, 0, False), ([255] * 64, 0, False),
              ([0 if (r + c) % 2 else 255 for r in range(8) for c in range(8)], 1, False),
              ([255 if (r + c) % 2 else 0 for r in range(8) for c in range(8)], 2, False)]
    for v in (255, 0):
        for pos in range(64):
            s = [128] * 64
            s[pos] = v
            blocks.append((s, pos % 3, False))
    blocks[-1] = (blocks[-1][0], blocks[-1][1], True)
    out, _, _ = await run_blocks(dut, blocks, rng)
    check_outputs(blocks, out)
    dut._log.info("%d directed blocks match", len(blocks))


@cocotb.test()
async def test_random_blocks(dut):
    """2400 seeded random blocks, back to back, stall-free."""
    await setup(dut)
    rng = random.Random(0x43)
    blocks = []
    for i in range(2400):
        kind = i % 4
        if kind == 0:
            s = [rng.randrange(256) for _ in range(64)]
        elif kind == 1:
            s = [rng.choice((0, 255)) for _ in range(64)]      # word-length stress
        elif kind == 2:
            s = spaced(rng, 64)
        else:
            base = rng.randrange(256)
            s = [min(255, max(0, base + rng.randrange(-12, 13))) for _ in range(64)]
        blocks.append((s, rng.randrange(3), i == 2399))
    out, first, lastc = await run_blocks(dut, blocks, rng)
    check_outputs(blocks, out)
    per_block = (lastc - first + 1) / len(blocks)
    dut._log.info("2400 random blocks match; %.1f cycles/block streamed", per_block)


@cocotb.test()
async def test_backpressure(dut):
    """Random stalls on S3 valid and S4 ready change nothing."""
    await setup(dut)
    rng = random.Random(0x44)
    blocks = [(spaced(rng, 64) if i % 2 else [rng.randrange(256) for _ in range(64)],
               rng.randrange(3), i == 59) for i in range(60)]
    for p_in, p_out in ((0.5, 0.5), (0.9, 0.15), (0.15, 0.9), (1.0, 0.05)):
        out, _, _ = await run_blocks(dut, blocks, rng, p_in, p_out, timeout=400000)
        check_outputs(blocks, out)
        dut._log.info("p_in=%.2f p_out=%.2f: %d blocks match", p_in, p_out, len(blocks))


@cocotb.test()
async def test_cycle_budget(dut):
    """0005 section 7 stage 2: at most 140 cycles per block, first S3 beat
    accepted to last S4 beat, stall-free (s3_valid high whenever data is
    ready to send, s4_ready always high), one block after reset."""
    await setup(dut)
    rng = random.Random(3)
    blk = [(T81[:], 0, True)]
    out, first, lastc = await run_blocks(dut, blk, rng)
    check_outputs(blk, out)
    n = lastc - first + 1
    dut._log.info("cycles per block (first S3 accept to last S4 beat, inclusive) = %d; "
                  "conditions: s3_valid held high, s4_ready held high, single block", n)
    assert n <= 140, f"{n} cycles per block exceeds the 140 budget"


@cocotb.test()
async def test_synthesis_no_latches(dut):
    """Yosys on the three files: transpose file is flops, no latch, no macro."""
    yosys = shutil.which("yosys")
    assert yosys, "yosys not found: the no-latch criterion cannot be checked"
    script = (f"read_verilog {RTL}/jc_xpose_rf.v {RTL}/jc_dct1d.v {RTL}/jc_dct.v; "
              "synth -top jc_dct -flatten; check -assert; stat")
    res = subprocess.run([yosys, "-q", "-p", script, "-p", "tee -o /dev/stdout stat"],
                         capture_output=True, text=True)
    assert res.returncode == 0, res.stdout + res.stderr
    text = res.stdout
    cells = {m.group(2): int(m.group(1))
             for m in re.finditer(r"^\s+(\d+)\s+(?:[\d.]+\s+)?(\$\w+|\w+)\s*$", text, re.M)}
    dut._log.info("yosys cells: %s", cells)
    assert not any("LATCH" in k.upper() or k.upper().startswith("$DLATCH") for k in cells), cells
    assert not any("mem" in k.lower() or "ram" in k.lower() for k in cells), cells
    flops = sum(v for k, v in cells.items() if "DFF" in k.upper())
    assert flops >= 64 * 14, f"only {flops} flops: transpose file not flops?"
