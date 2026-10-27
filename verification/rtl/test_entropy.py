"""Entropy stage bench: jc_zigzag -> jc_huff -> jc_bitpack (issue #45).

The reference below is written from spec section 6 only (zig-zag table,
DC difference per component, (run << 4) | size symbols, ZRL per 16 zeros,
EOB, additional bits, MSB-first packing, 0xFF stuffing, 1-bit padding). It
does not import the golden encoder; the Annex K *tables* come from the golden
module as data, and the worked-example bytes are pinned independently.

Each test frame is a list of (comp, zz_values) blocks in scan order; the
bench feeds natural-index coefficient beats to jc_zigzag (in a shuffled
order, as the DCT emits them) and compares the byte stream, byte for byte,
with the reference. Unit-level goal: the formulas. The comparison against the
golden encoder as an item-5 claim is issue #34.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import jpeg_golden as g  # Annex K table data and canonical code builder only

# Spec section 6, T.81 Figure A.6: natural index of each zig-zag position.
ZIGZAG = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
]

# Spec section 6 worked example: the section 5 block, quantized (zig-zag).
EXAMPLE_ZZ = [-26, -3, 0, -3, -2, -6, 2, -4, 1, -3, 1, 1, 5, 1, 2, -1,
              1, -1, 2, 0, 0, 0, 0, 0, -1, -1] + [0] * 38
EXAMPLE_BYTES = bytes.fromhex("c54d8b0b4650994b021bd057")

DC_LUMA = g.build_codes(g.ANNEX_K_DC_LUMA_BITS, g.ANNEX_K_DC_LUMA_VALS)
AC_LUMA = g.build_codes(g.ANNEX_K_AC_LUMA_BITS, g.ANNEX_K_AC_LUMA_VALS)
DC_CHROMA = g.build_codes(g.ANNEX_K_DC_CHROMA_BITS, g.ANNEX_K_DC_CHROMA_VALS)
AC_CHROMA = g.build_codes(g.ANNEX_K_AC_CHROMA_BITS, g.ANNEX_K_AC_CHROMA_VALS)


# ------------------------------------------------------------- reference --

def ref_scan(blocks):
    """Entropy-coded segment of a frame, from spec section 6."""
    bits = []                       # list of (value, nbits)
    pred = [0, 0, 0]
    for comp, zz in blocks:
        dc_t = DC_LUMA if comp == 0 else DC_CHROMA
        ac_t = AC_LUMA if comp == 0 else AC_CHROMA

        def additional(v, s):
            return (v if v >= 0 else v + (1 << s) - 1) & ((1 << s) - 1)

        diff = zz[0] - pred[comp]
        pred[comp] = zz[0]
        s = abs(diff).bit_length()
        bits.append(dc_t[s])
        bits.append((additional(diff, s), s))
        run = 0
        for k in range(1, 64):
            v = zz[k]
            if v == 0:
                run += 1
                continue
            while run >= 16:
                bits.append(ac_t[0xF0])
                run -= 16
            s = abs(v).bit_length()
            bits.append(ac_t[(run << 4) | s])
            bits.append((additional(v, s), s))
            run = 0
        if run > 0:
            bits.append(ac_t[0x00])
    out = bytearray()
    acc, n = 0, 0
    for val, ln in bits:
        acc = (acc << ln) | val
        n += ln
        while n >= 8:
            n -= 8
            b = (acc >> n) & 0xFF
            out.append(b)
            if b == 0xFF:
                out.append(0)
        acc &= (1 << n) - 1
    if n:
        b = ((acc << (8 - n)) | ((1 << (8 - n)) - 1)) & 0xFF
        out.append(b)
        if b == 0xFF:
            out.append(0)
    return bytes(out)


# ----------------------------------------------------------- memory image --

def ac_index(sym):
    if sym == 0x00:
        return 160
    if sym == 0xF0:
        return 161
    return 10 * (sym >> 4) + (sym & 0xF) - 1


def word(table, sym):
    code, ln = table[sym]
    return (ln << 16) | code


async def load_tables(dut):
    """Annex K words in the section 13 layout (M1: AC0, DC0, DC1; M2: AC1)."""
    dut.m1_wr_en.value = 0
    dut.m2_wr_en.value = 0
    entries = []
    for sym in AC_LUMA:
        entries.append((1, ac_index(sym), word(AC_LUMA, sym)))
    for size in range(12):
        entries.append((1, 162 + size, word(DC_LUMA, size)))
        entries.append((1, 174 + size, word(DC_CHROMA, size)))
    for sym in AC_CHROMA:
        entries.append((2, ac_index(sym), word(AC_CHROMA, sym)))
    for mem, addr, val in entries:
        port = dut.m1_wr_en if mem == 1 else dut.m2_wr_en
        a = dut.m1_wr_addr if mem == 1 else dut.m2_wr_addr
        d = dut.m1_wr_data if mem == 1 else dut.m2_wr_data
        port.value = 1
        a.value = addr
        d.value = val
        await RisingEdge(dut.clk)
        port.value = 0
    dut.m1_wr_en.value = 0
    dut.m2_wr_en.value = 0


# ------------------------------------------------------------------ bench --

async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.in_idx.value = 0
    dut.in_coef.value = 0
    dut.in_tag.value = 0
    dut.out_ready.value = 1
    dut.m1_stall.value = 0
    dut.m2_stall.value = 0
    dut.m1_wr_en.value = 0
    dut.m2_wr_en.value = 0
    dut.m1_wr_addr.value = 0
    dut.m2_wr_addr.value = 0
    dut.m1_wr_data.value = 0
    dut.m2_wr_data.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await load_tables(dut)


def frame_beats(blocks, rng, order):
    """S4 beats for a frame: (idx, coef15, tag) with block-wise shuffling."""
    beats = []
    for n, (comp, zz) in enumerate(blocks):
        nat = [0] * 64
        for k in range(64):
            nat[ZIGZAG[k]] = zz[k]
        idxs = list(range(64))
        if order == "col":
            idxs = [r * 8 + c for c in range(8) for r in range(8)]
        elif order == "random":
            rng.shuffle(idxs)
        last = 1 if n == len(blocks) - 1 else 0
        for i in idxs:
            beats.append((i, nat[i] & 0x7FFF, (last << 2) | comp))
    return beats


async def run_frames(dut, frames, rng, in_gap=0.0, out_stall=0.0,
                     mem_stall=0.0, order="random", max_cycles=2_000_000):
    """Feed frames back to back, collect bytes; return one bytes per frame."""
    beats = []
    for blocks in frames:
        beats.extend(frame_beats(blocks, rng, order))
    state = {"i": 0, "bytes": [bytearray()], "done": False, "err": None}

    async def drive():
        i = 0
        valid = 0
        while i < len(beats):
            if not valid and rng.random() >= in_gap:
                idx, coef, tag = beats[i]
                dut.in_idx.value = idx
                dut.in_coef.value = coef
                dut.in_tag.value = tag
                dut.in_valid.value = 1
                valid = 1
            await RisingEdge(dut.clk)
            if valid and dut.in_ready.value == 1:
                i += 1
                valid = 0
                dut.in_valid.value = 0
        dut.in_valid.value = 0

    async def collect():
        nframes = len(frames)
        done = 0
        while done < nframes:
            ready = 0 if rng.random() < out_stall else 1
            dut.out_ready.value = ready
            dut.m1_stall.value = 1 if rng.random() < mem_stall else 0
            dut.m2_stall.value = 1 if rng.random() < mem_stall else 0
            await RisingEdge(dut.clk)
            # sampled values are those present at the edge
            if dut.out_valid.value == 1 and ready:
                state["bytes"][-1].append(int(dut.out_data.value))
                if dut.out_last.value == 1:
                    done += 1
                    state["bytes"].append(bytearray())
        state["done"] = True

    cocotb.start_soon(drive())
    col = cocotb.start_soon(collect())
    cycles = 0
    while not state["done"]:
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < max_cycles, "timeout: frame did not complete"
    await col
    # drain a few cycles: nothing more may appear after the final byte
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert not (dut.out_valid.value == 1), "extra byte after out_last"
    return [bytes(b) for b in state["bytes"][:-1]], cycles


async def check(dut, frames, rng, **kw):
    got, cycles = await run_frames(dut, frames, rng, **kw)
    assert len(got) == len(frames)
    for n, (blocks, data) in enumerate(zip(frames, got)):
        exp = ref_scan(blocks)
        assert data == exp, (
            f"frame {n}: got {data.hex()} expected {exp.hex()}")
    return cycles


# ------------------------------------------------------------- stimulus --

def rand_block(rng, comp, density=None, big=False):
    dens = rng.choice([0.02, 0.1, 0.3, 0.7, 1.0]) if density is None else density
    zz = [0] * 64
    zz[0] = rng.randint(-1024, 1016) if big or rng.random() < 0.3 else rng.randint(-60, 60)
    for k in range(1, 64):
        if rng.random() < dens:
            m = rng.choice([1, 1, 1, 2, 3, 7, 15, 63, 255, 1023])
            m = rng.randint(1, m)
            zz[k] = m if rng.random() < 0.5 else -m
    return (comp, zz)


def mcu(rng, **kw):
    return [rand_block(rng, c, **kw) for c in (0, 0, 0, 0, 1, 2)]


# ----------------------------------------------------------------- tests --

@cocotb.test()
async def test_worked_example(dut):
    """Spec section 6: the section 5 block, Annex K luma tables, 12 bytes."""
    await reset(dut)
    assert ref_scan([(0, EXAMPLE_ZZ)]) == EXAMPLE_BYTES   # reference sanity
    got, _ = await run_frames(dut, [[(0, EXAMPLE_ZZ)]], random.Random(1))
    assert got[0] == EXAMPLE_BYTES, got[0].hex()


@cocotb.test()
async def test_zigzag_order(dut):
    """Every natural-order write order yields the same bytes."""
    await reset(dut)
    rng = random.Random(2)
    blocks = [rand_block(rng, c, density=0.5) for c in (0, 1, 2)]
    for order in ("row", "col", "random"):
        await check(dut, [blocks], rng, order=order)


@cocotb.test()
async def test_all_zero_block(dut):
    """EOB only after the DC symbol."""
    await reset(dut)
    rng = random.Random(3)
    await check(dut, [[(0, [0] * 64)]], rng)
    await check(dut, [[(1, [0] * 64), (2, [0] * 64)]], rng)


@cocotb.test()
async def test_position_63(dut):
    """Position 63 non-zero: no EOB. Also 62 and 63 both set."""
    await reset(dut)
    rng = random.Random(4)
    for comp in (0, 1):
        for v in (1, -1, 5, -1023, 1023):
            zz = [0] * 64
            zz[0] = 3
            zz[63] = v
            await check(dut, [[(comp, zz)]], rng)
    zz = [0] * 64
    zz[62], zz[63] = -2, 2
    await check(dut, [[(0, zz)]], rng)
    zz = [1] * 64
    await check(dut, [[(0, zz), (1, zz)]], rng)


@cocotb.test()
async def test_zrl(dut):
    """Zero runs of 15, 16, 17, 31, 32, 33, 47 and a trailing run >= 16."""
    await reset(dut)
    rng = random.Random(5)
    for gap in (14, 15, 16, 17, 31, 32, 33, 47, 48, 62):
        zz = [0] * 64
        zz[0] = -7
        zz[1 + gap] = 9 if gap % 2 else -9
        for comp in (0, 2):
            await check(dut, [[(comp, zz)]], rng)
    # several runs in one block, and ZRL immediately before position 63
    zz = [0] * 64
    zz[1], zz[18], zz[35], zz[52], zz[63] = 1, -1, 2, -2, 3
    await check(dut, [[(0, zz)]], rng)
    # a single non-zero then 62 zeros: EOB only, no ZRL
    zz = [0] * 64
    zz[1] = 4
    await check(dut, [[(0, zz)]], rng)


@cocotb.test()
async def test_ff_stuffing(dut):
    """Scans containing FF 00 mid-stream and ending in FF 00 (padding byte 0xFF)."""
    await reset(dut)
    rng = random.Random(6)
    mid, tail = 0, 0
    tries = 0
    while (mid < 6 or tail < 3) and tries < 20000:
        tries += 1
        blk = [rand_block(rng, rng.choice((0, 1, 2)), density=rng.choice((0.1, 0.4)))
               for _ in range(rng.randint(1, 2))]
        exp = ref_scan(blk)
        is_mid = b"\xff\x00" in exp[:-2]
        is_tail = exp.endswith(b"\xff\x00")
        want = (is_mid and mid < 6) or (is_tail and tail < 3)
        if not want:
            continue
        mid += is_mid
        tail += is_tail
        await check(dut, [blk], rng)
    assert mid >= 6 and tail >= 3, (mid, tail, tries)
    dut._log.info("stuffing cases mid=%d tail=%d tries=%d", mid, tail, tries)


@cocotb.test()
async def test_dc_chain(dut):
    """DC prediction per component across MCUs; reset after the frame."""
    await reset(dut)
    rng = random.Random(7)
    dcs = [(10, -3, 40), (-50, 7, 41), (1016, -1024, 1000), (-1024, 1016, -1024),
           (0, 0, 0), (5, 5, 5)]
    blocks = []
    for y, cb, cr in dcs:
        for dy in (y, y - 1, y + 2, y):
            z = [0] * 64
            z[0] = max(-1024, min(1016, dy))
            blocks.append((0, z))
        z = [0] * 64
        z[0] = cb
        blocks.append((1, z))
        z = [0] * 64
        z[0] = cr
        blocks.append((2, z))
    # two identical frames back to back: predictors must restart at 0
    await check(dut, [blocks, blocks], rng)


@cocotb.test()
async def test_extreme_sizes(dut):
    """Size-10 AC at +-1023 and DC size 11 (difference +-2040)."""
    await reset(dut)
    rng = random.Random(8)
    blocks = []
    for comp in (0, 1, 2):
        z = [0] * 64
        z[0] = 1016
        z[1], z[2], z[5], z[63] = 1023, -1023, 512, -1023
        blocks.append((comp, z))
        z = [0] * 64
        z[0] = -1024
        z[1], z[3], z[20] = -1023, 1023, -512
        blocks.append((comp, z))
    await check(dut, [blocks], rng)


@cocotb.test()
async def test_back_pressure(dut):
    """Output stalls, input gaps and slow memory lose no bits."""
    await reset(dut)
    rng = random.Random(9)
    frames = [mcu(rng) + mcu(rng) for _ in range(3)]
    for out_stall, in_gap, mem_stall in ((0.9, 0.0, 0.0), (0.5, 0.5, 0.5),
                                         (0.0, 0.0, 0.8), (0.97, 0.3, 0.3)):
        await check(dut, frames, rng, out_stall=out_stall, in_gap=in_gap,
                    mem_stall=mem_stall)


@cocotb.test()
async def test_random_blocks(dut):
    """600 seeded random blocks (100 MCUs in 4 frames), mixed stalls."""
    await reset(dut)
    rng = random.Random(10)
    total = 0
    for f in range(4):
        frame = []
        for _ in range(25):
            frame.extend(mcu(rng, big=True) if f == 3 else mcu(rng))
        total += len(frame)
        await check(dut, [frame], rng, out_stall=0.2 * f, in_gap=0.1 * (f % 2),
                    mem_stall=0.1 * f)
    assert total >= 500
    # grey-style stream: only comp 0, many frames of one block
    singles = [[rand_block(rng, 0)] for _ in range(60)]
    await check(dut, singles, rng)
