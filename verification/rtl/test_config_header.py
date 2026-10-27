"""cocotb bench for the configuration stage (issue #46): jc_cfg_regs,
jc_table_load, jc_header_gen and jc_out_mux, with behavioural M1/M2 memories.

Oracles are written from the spec text, independently of the RTL and of the
golden encoder's framing code (only the Annex K table *data* is imported):
  * the file header is assembled from spec section 7 (`ref_header`);
  * the QOI header and end marker from spec section 8;
  * canonical codes from T.81 Annex C (`annexc`), placed at the record 0005
    symbol index in `{len[4:0], code[15:0]}` words (spec section 13).
Unit-level goal: the formulas. Comparison with the golden encoder as an
item-5 claim is issue #34.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import jpeg_golden as g  # Annex K table data only

# ---------------------------------------------------------------- tables --

TABLES = ("q0", "q1", "dc0", "ac0", "dc1", "ac1")
WIN = {"q0": 0x040, "q1": 0x080, "dc0": 0x100, "ac0": 0x140,
       "dc1": 0x200, "ac1": 0x240}
WIN_LEN = {"q0": 64, "q1": 64, "dc0": 28, "ac0": 178, "dc1": 28, "ac1": 178}
# (raw mem, raw base word) and, for DHT, (lookup mem, lookup base, entries)
RAW = {"q0": (1, 186), "q1": (1, 202), "dc0": (1, 218), "ac0": (2, 162),
       "dc1": (1, 225), "ac1": (2, 207)}
LOOK = {"dc0": (1, 162, 12), "ac0": (1, 0, 162),
        "dc1": (1, 174, 12), "ac1": (2, 0, 162)}

ANNEX_K = {
    "q0": bytes(g.ANNEX_K_LUMA_QUANT_ZZ),
    "q1": bytes(g.ANNEX_K_CHROMA_QUANT_ZZ),
    "dc0": bytes(g.ANNEX_K_DC_LUMA_BITS) + bytes(g.ANNEX_K_DC_LUMA_VALS),
    "ac0": bytes(g.ANNEX_K_AC_LUMA_BITS) + bytes(g.ANNEX_K_AC_LUMA_VALS),
    "dc1": bytes(g.ANNEX_K_DC_CHROMA_BITS) + bytes(g.ANNEX_K_DC_CHROMA_VALS),
    "ac1": bytes(g.ANNEX_K_AC_CHROMA_BITS) + bytes(g.ANNEX_K_AC_CHROMA_VALS),
}

E_BUSY, E_ZERO_Q, E_BAD_HUFF, E_CONFIG, E_ADDR, E_TABLE = 1, 2, 3, 4, 5, 6
MODE_COLOUR, MODE_GREY, MODE_QOI = 0, 1, 2
REG_MODE, REG_W, REG_H, REG_CMD = 0x000, 0x001, 0x003, 0x005


def annexc(payload):
    """T.81 Annex C: {symbol: (code, length)} from a DHT payload."""
    bits, vals = payload[:16], payload[16:]
    codes, code, k = {}, 0, 0
    for length in range(1, 17):
        for _ in range(bits[length - 1]):
            codes[vals[k]] = (code, length)
            code += 1
            k += 1
        code <<= 1
    return codes


def sym_index(table, sym):
    """Record 0005 section 4: AC 10*run+size-1, 160 EOB, 161 ZRL; DC = size."""
    if table.startswith("dc"):
        return sym
    if sym == 0x00:
        return 160
    if sym == 0xF0:
        return 161
    return 10 * (sym >> 4) + (sym & 15) - 1


def expected_lookups(table, payload):
    """{(mem, addr): word} over the whole lookup region of a DHT table."""
    mem, base, n = LOOK[table]
    out = {(mem, base + i): 0 for i in range(n)}
    for sym, (code, length) in annexc(payload).items():
        out[(mem, base + sym_index(table, sym))] = (length << 16) | code
    return out


def kraft_ok(bits):
    code = 0
    for length in range(1, 17):
        code += bits[length - 1]
        if code > (1 << length):
            return False
        code <<= 1
    return True


def valid_symbols(table):
    if table.startswith("dc"):
        return list(range(12))
    return [0x00, 0xF0] + [(r << 4) | s for r in range(16) for s in range(1, 11)]


def random_dht(rng, table, nsym=None):
    """A valid DHT payload: random Kraft-valid lengths, shuffled symbols."""
    syms = valid_symbols(table)
    if nsym is None:
        nsym = rng.randint(1, len(syms))
    vals = rng.sample(syms, nsym)
    while True:
        bits, free, rem = [], 2, nsym
        for length in range(1, 17):
            c = min(free, rem, rng.choice([0, 0, 1, 2, 3, 7, 40, 200]))
            if length == 16:
                c = min(free, rem)
            bits.append(c)
            rem -= c
            free = (free - c) * 2
        if rem == 0 and kraft_ok(bits):
            return bytes(bits) + bytes(vals)


# ---------------------------------------------------------- file framing --

def segment(marker, payload):
    return bytes([0xFF, marker]) + (len(payload) + 2).to_bytes(2, "big") + payload


def ref_header(mode, w, h, tables):
    """Spec section 7, assembled from the text. `tables` maps name -> payload."""
    if mode == MODE_QOI:
        return (b"qoif" + w.to_bytes(4, "big") + h.to_bytes(4, "big")
                + bytes([3, 0]))
    colour = mode == MODE_COLOUR
    out = b"\xff\xd8"
    out += segment(0xE0, b"JFIF\x00" + bytes([1, 1, 0, 0, 1, 0, 1, 0, 0]))
    out += segment(0xDB, b"\x00" + tables["q0"][:64])
    if colour:
        out += segment(0xDB, b"\x01" + tables["q1"][:64])
    comps = (b"\x01\x22\x00\x02\x11\x01\x03\x11\x01" if colour
             else b"\x01\x11\x00")
    out += segment(0xC0, bytes([8]) + h.to_bytes(2, "big") + w.to_bytes(2, "big")
                   + bytes([3 if colour else 1]) + comps)
    for tcth, name in ((0x00, "dc0"), (0x10, "ac0"), (0x01, "dc1"), (0x11, "ac1")):
        if colour or name in ("dc0", "ac0"):
            p = tables[name]
            out += segment(0xC4, bytes([tcth]) + p[:16 + sum(p[:16])])
    sos = (b"\x03\x01\x00\x02\x11\x03\x11" if colour else b"\x01\x01\x00") + b"\x00\x3f\x00"
    out += segment(0xDA, sos)
    return out


def ref_trailer(mode):
    return bytes(7) + b"\x01" if mode == MODE_QOI else b"\xff\xd9"


# ------------------------------------------------------------------ bench --

class Env:
    """Per-cycle random stalls on out_ready and the two memories."""
    mem_stall = 0.0
    out_stall = 0.0
    rng = random.Random(0)


async def env_driver(dut):
    while True:
        dut.m1_stall.value = int(Env.rng.random() < Env.mem_stall)
        dut.m2_stall.value = int(Env.rng.random() < Env.mem_stall)
        dut.out_ready.value = int(Env.rng.random() >= Env.out_stall)
        await RisingEdge(dut.clk)


async def reset(dut, wait=True):
    Env.mem_stall = Env.out_stall = 0.0
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.cfg_valid.value = 0
    dut.cfg_addr.value = 0
    dut.cfg_wdata.value = 0
    dut.bp_valid.value = 0
    dut.bp_data.value = 0
    dut.bp_last.value = 0
    dut.qoi_valid.value = 0
    dut.qoi_data.value = 0
    dut.qoi_last.value = 0
    dut.out_ready.value = 1
    dut.m1_stall.value = 0
    dut.m2_stall.value = 0
    dut.m1_dbg_addr.value = 0
    dut.m2_dbg_addr.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    cocotb.start_soon(env_driver(dut))
    await RisingEdge(dut.clk)
    if wait:
        assert dut.status_busy.value == 1, "reset load must hold busy"
        await wait_idle(dut)


async def wait_idle(dut, cap=60000):
    for _ in range(cap):
        await RisingEdge(dut.clk)
        if dut.status_idle.value == 1:
            return
    raise AssertionError("timeout waiting for idle")


async def cfg_write(dut, addr, val):
    dut.cfg_valid.value = 1
    dut.cfg_addr.value = addr
    dut.cfg_wdata.value = val
    while True:
        await RisingEdge(dut.clk)
        if dut.cfg_ready.value == 1:
            break
    dut.cfg_valid.value = 0


async def write_reg16(dut, addr, v):
    await cfg_write(dut, addr, v & 0xFF)
    await cfg_write(dut, addr + 1, v >> 8)


async def write_table(dut, name, payload):
    assert len(payload) <= WIN_LEN[name]
    for i, b in enumerate(payload):
        await cfg_write(dut, WIN[name] + i, b)


async def configure(dut, mode, w, h):
    await cfg_write(dut, REG_MODE, mode)
    await write_reg16(dut, REG_W, w)
    await write_reg16(dut, REG_H, h)


async def commit(dut):
    await cfg_write(dut, REG_CMD, 2)
    await RisingEdge(dut.clk)
    await wait_idle(dut)


async def clear_error(dut):
    await cfg_write(dut, REG_CMD, 4)
    await RisingEdge(dut.clk)
    assert dut.err_cause.value == 0 and dut.status_error.value == 0


def cause(dut):
    return int(dut.err_cause.value)


async def snapshot(dut):
    """{(mem, addr): word} for all of M1 and M2 (X words read as None)."""
    snap = {}
    for mem, a, d in ((1, dut.m1_dbg_addr, dut.m1_dbg_data),
                      (2, dut.m2_dbg_addr, dut.m2_dbg_data)):
        for i in range(256):
            a.value = i
            await Timer(1, unit="ns")
            v = d.value
            snap[(mem, i)] = int(v) if v.is_resolvable else None
    return snap


def raw_bytes(snap, table, n):
    mem, base = RAW[table]
    out = bytearray()
    for i in range(n):
        w = snap[(mem, base + (i >> 2))]
        out.append(None if w is None else (w >> (8 * (i & 3))) & 0xFF)
    return bytes(out)


def check_tables(snap, tables):
    """Raw payload bytes and lookup words in `snap` match `tables`."""
    for name, payload in tables.items():
        if name.startswith("q"):
            n = 64
        else:
            n = 16 + sum(payload[:16])
        assert raw_bytes(snap, name, n) == payload[:n], f"raw {name}"
        if name in LOOK:
            for key, word in expected_lookups(name, payload).items():
                assert snap[key] == word, (
                    f"{name} lookup {key}: got {snap[key]:#x} want {word:#x}")


def lookup_view(snap, names):
    """Lookup words of the named DHT tables."""
    out = {}
    for n in names:
        mem, base, cnt = LOOK[n]
        for i in range(cnt):
            out[(mem, base + i)] = snap[(mem, base + i)]
    return out


async def run_frame(dut, mode, w, h, scan, tables, *, expect_header=True,
                    max_cycles=200000):
    """Configure, start, feed `scan`, collect the file. Returns its bytes."""
    await configure(dut, mode, w, h)
    await cfg_write(dut, REG_CMD, 1)
    qoi = mode == MODE_QOI
    v, d, l = ((dut.qoi_valid, dut.qoi_data, dut.qoi_last) if qoi
               else (dut.bp_valid, dut.bp_data, dut.bp_last))
    rdy = dut.qoi_ready if qoi else dut.bp_ready
    got = bytearray()
    done = False
    i = 0
    cycles = 0
    while not done:
        if i < len(scan):
            v.value = 1
            d.value = scan[i]
            l.value = int(i == len(scan) - 1)
        else:
            v.value = 0
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < max_cycles, "timeout: file did not complete"
        if i < len(scan) and rdy.value == 1:
            i += 1
        if dut.out_valid.value == 1 and dut.out_ready.value == 1:
            got.append(int(dut.out_data.value))
            if dut.out_last.value == 1:
                done = True
    v.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert not (dut.out_valid.value == 1), "extra byte after out_last"
    assert i == len(scan), "scan not fully consumed"
    return bytes(got)


def rand_scan(rng, n):
    return bytes(rng.randrange(256) for _ in range(n))


async def check_frame(dut, mode, w, h, tables, rng):
    scan = rand_scan(rng, rng.randint(1, 40))
    got = await run_frame(dut, mode, w, h, scan, tables)
    exp = ref_header(mode, w, h, tables) + scan + ref_trailer(mode)
    assert got == exp, f"mode {mode} {w}x{h}: file differs\n got {got.hex()}\n exp {exp.hex()}"
    await wait_idle(dut)
    return got


def scan_of(file_bytes, hdr):
    """The bytes between the header and the 2-byte EOI."""
    return file_bytes[len(hdr):-2]


# ----------------------------------------------------------------- tests --

@cocotb.test()
async def test_reset_defaults(dut):
    """Reset loads Annex K through the table path (busy until done); a
    header with no table write equals the Annex K header (625 B + EOI)."""
    await reset(dut, wait=False)
    assert dut.status_busy.value == 1 and dut.status_idle.value == 0
    await wait_idle(dut)
    assert dut.status_error.value == 0 and cause(dut) == 0
    snap = await snapshot(dut)
    check_tables(snap, ANNEX_K)
    rng = random.Random(10)
    got = await check_frame(dut, MODE_COLOUR, 640, 480, ANNEX_K, rng)
    hdr = ref_header(MODE_COLOUR, 640, 480, ANNEX_K)
    # spec section 7: 2 + 18 + 2*69 + 19 + (2*183 + 2*33) + 14 + 2 = 625 bytes,
    # the last 2 being EOI, so the header proper is 623 and the file 625 + scan.
    # (Record 0005 section 7 adds EOI again and says 627; that is off by two.)
    assert len(hdr) == 623 and got.startswith(hdr)
    assert len(got) - len(scan_of(got, hdr)) == 625
    # golden framing agrees on the same bytes (cross-check, not the oracle)
    q = g.ANNEX_K_LUMA_QUANT_ZZ, g.ANNEX_K_CHROMA_QUANT_ZZ
    assert hdr == g._header(640, 480, "colour", *q)


@cocotb.test()
async def test_header_sizes_and_modes(dut):
    """Colour, grey and QOI headers/trailers; sizes 1 and 65535."""
    await reset(dut)
    rng = random.Random(11)
    for mode in (MODE_COLOUR, MODE_GREY, MODE_QOI):
        for w, h in ((1, 1), (65535, 65535), (16, 16), (1, 65535), (65535, 1),
                     (100, 60), (640, 480)):
            await check_frame(dut, mode, w, h, ANNEX_K, rng)
    # geometry outputs
    await configure(dut, MODE_COLOUR, 100, 60)
    await RisingEdge(dut.clk)
    assert (int(dut.mcu_cols.value), int(dut.mcu_rows.value)) == (7, 4)
    await configure(dut, MODE_GREY, 65535, 9)
    await RisingEdge(dut.clk)
    assert (int(dut.mcu_cols.value), int(dut.mcu_rows.value)) == (8192, 2)
    await configure(dut, MODE_COLOUR, 65535, 65535)
    await RisingEdge(dut.clk)
    assert (int(dut.mcu_cols.value), int(dut.mcu_rows.value)) == (4096, 4096)


@cocotb.test()
async def test_header_with_stalls(dut):
    """Header and trailer survive random memory and output stalls."""
    await reset(dut)
    rng = random.Random(12)
    Env.mem_stall, Env.out_stall = 0.5, 0.5
    for mode in (MODE_COLOUR, MODE_GREY, MODE_QOI):
        await check_frame(dut, mode, 33, 17, ANNEX_K, rng)


@cocotb.test()
async def test_canonical_codes_and_replay(dut):
    """Custom valid tables: lookup words equal an independent Annex C
    computation (including 16-bit codes) and the header replays the payloads."""
    await reset(dut)
    rng = random.Random(13)
    tables = dict(ANNEX_K)

    # a chain with one code per length: the 16-bit code is 0xFFFE
    chain_ac = bytes([1] * 16) + bytes([0x01, 0x02, 0x03, 0x11, 0x12, 0x21, 0x22,
                                        0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91,
                                        0xA1, 0xF0])
    assert annexc(chain_ac)[0xF0] == (0xFFFE, 16)
    chain_dc = bytes([1] * 11 + [0] * 5) + bytes(range(11))
    # single code of length 16 (value 0)
    lone_ac = bytes([0] * 15 + [1]) + bytes([0x00])
    for round_no in range(4):
        if round_no == 0:
            new = {"ac0": chain_ac, "dc0": chain_dc, "ac1": lone_ac,
                   "dc1": bytes([0, 2]) + bytes(14) + bytes([0, 5])}
        else:
            new = {"ac0": random_dht(rng, "ac0"), "dc0": random_dht(rng, "dc0"),
                   "ac1": random_dht(rng, "ac1", 162),
                   "dc1": random_dht(rng, "dc1")}
        new["q0"] = bytes(rng.randint(1, 255) for _ in range(64))
        new["q1"] = bytes(rng.randint(1, 255) for _ in range(64))
        for name, payload in new.items():
            await write_table(dut, name, payload)
        await commit(dut)
        assert cause(dut) == 0
        tables.update(new)
        snap = await snapshot(dut)
        check_tables(snap, tables)
        await check_frame(dut, MODE_COLOUR, 48, 32, tables, rng)
        await check_frame(dut, MODE_GREY, 48, 32, tables, rng)


@cocotb.test()
async def test_partial_commit_keeps_other_tables(dut):
    """Only dirty tables are rebuilt; the others keep their lookups."""
    await reset(dut)
    rng = random.Random(14)
    before = await snapshot(dut)
    new_ac0 = random_dht(rng, "ac0", 60)
    await write_table(dut, "ac0", new_ac0)
    await commit(dut)
    assert cause(dut) == 0
    after = await snapshot(dut)
    tables = dict(ANNEX_K)
    tables["ac0"] = new_ac0
    check_tables(after, tables)
    others = ("dc0", "dc1", "ac1")
    assert lookup_view(before, others) == lookup_view(after, others)
    # a commit with nothing dirty is a no-op
    await commit(dut)
    assert (await snapshot(dut)) == after


@cocotb.test()
async def test_zero_quant_rejected(dut):
    """Q entry 0 -> ZERO_QUANT; the table stays invalid, others unchanged."""
    await reset(dut)
    rng = random.Random(15)
    for pos in (0, 1, 31, 63):
        before = await snapshot(dut)
        bad = bytearray(ANNEX_K["q1"])
        bad[pos] = 0
        await write_table(dut, "q1", bytes(bad))
        await commit(dut)
        assert cause(dut) == E_ZERO_Q and dut.status_error.value == 1
        mid = await snapshot(dut)
        for name in ("dc0", "ac0", "dc1", "ac1"):
            assert lookup_view(before, [name]) == lookup_view(mid, [name])
        # start refused: TABLE_INVALID is not recorded over the first cause,
        # but nothing may be emitted and the chip stays idle
        await cfg_write(dut, REG_CMD, 4)
        await configure(dut, MODE_COLOUR, 16, 16)
        await cfg_write(dut, REG_CMD, 1)
        for _ in range(40):
            await RisingEdge(dut.clk)
            assert dut.out_valid.value == 0 and dut.status_idle.value == 1
        assert cause(dut) == E_TABLE
        # grey needs only table 0 and is still allowed
        await clear_error(dut)
        await check_frame(dut, MODE_GREY, 16, 16, ANNEX_K, rng)
        await clear_error(dut)
        # repair
        await write_table(dut, "q1", ANNEX_K["q1"])
        await commit(dut)
        assert cause(dut) == 0
        await check_frame(dut, MODE_COLOUR, 16, 16, ANNEX_K, rng)


def bad_tables():
    """(label, table, payload, writes_whole_payload) rejection cases."""
    ac_ok = [0x00, 0x01, 0x02]
    return [
        ("dc symbol 12", "dc0", bytes([0, 0, 0, 2] + [0] * 12) + bytes([0, 12])),
        ("dc symbol 255", "dc1", bytes([0, 0, 0, 2] + [0] * 12) + bytes([3, 255])),
        ("dc 13 symbols", "dc0", bytes([0, 0, 0, 13] + [0] * 12) + bytes(range(12))),
        ("ac size 11", "ac0", bytes([0, 0, 0, 0, 0, 0, 0, 3] + [0] * 8)
         + bytes([0x00, 0x0B, 0x01])),
        ("ac size 0 run 1", "ac1", bytes([0, 0, 0, 0, 0, 0, 0, 3] + [0] * 8)
         + bytes([0x00, 0x10, 0x01])),
        ("ac 0xFF", "ac0", bytes([0, 0, 0, 0, 0, 0, 0, 3] + [0] * 8)
         + bytes([0xFF, 0x01, 0x02])),
        ("ac 0xE0", "ac1", bytes([0, 0, 0, 0, 0, 0, 0, 3] + [0] * 8)
         + bytes([0x01, 0xE0, 0x02])),
        ("ac size 11 last", "ac0", bytes([0, 0, 0, 0, 0, 0, 0, 3] + [0] * 8)
         + bytes(ac_ok[:2] + [0xFB])),
        ("ac 163 symbols", "ac0", bytes([0] * 15 + [163]) + b""),
        ("dc kraft 3x1-bit", "dc0", bytes([3] + [0] * 15) + bytes([0, 1, 2])),
        ("ac kraft 3x1-bit", "ac1", bytes([3] + [0] * 15) + bytes(ac_ok)),
        ("ac kraft 2x1 + 1x2", "ac0", bytes([2, 1] + [0] * 14) + bytes(ac_ok)),
        ("ac kraft overfull deep", "ac1",
         bytes([0] * 15 + [0]) [:0] + bytes([0, 4, 1] + [0] * 13) + bytes([0, 1, 2, 3, 0x11])),
    ]


@cocotb.test()
async def test_bad_huffman_rejected(dut):
    """Each DHT rejection rule: BAD_HUFFMAN, other tables untouched, start
    refused with TABLE_INVALID, repair works."""
    await reset(dut)
    rng = random.Random(16)
    for label, name, payload in [(a, b, c) for a, b, c in bad_tables()]:
        before = await snapshot(dut)
        await write_table(dut, name, payload)
        await commit(dut)
        assert cause(dut) == E_BAD_HUFF, f"{label}: cause {cause(dut)}"
        mid = await snapshot(dut)
        others = [n for n in ("dc0", "ac0", "dc1", "ac1") if n != name]
        assert lookup_view(before, others) == lookup_view(mid, others), label
        for q in ("q0", "q1"):
            assert raw_bytes(before, q, 64) == raw_bytes(mid, q, 64), label
        await clear_error(dut)
        await configure(dut, MODE_COLOUR, 16, 16)
        await cfg_write(dut, REG_CMD, 1)
        for _ in range(40):
            await RisingEdge(dut.clk)
            assert dut.out_valid.value == 0 and dut.status_idle.value == 1, label
        assert cause(dut) == E_TABLE, label
        await clear_error(dut)
        await write_table(dut, name, ANNEX_K[name])
        await commit(dut)
        assert cause(dut) == 0, label
        check_tables(await snapshot(dut), ANNEX_K)


@cocotb.test()
async def test_valid_boundaries_accepted(dut):
    """Edge tables that must NOT be rejected: size-10 symbols, run-15 symbols,
    ZRL/EOB only, DC symbols 0 and 11, exactly 12 DC and 162 AC symbols."""
    await reset(dut)
    rng = random.Random(17)
    cases = {
        "ac0": bytes([0, 2] + [0] * 14) + bytes([0xFA, 0xF1]),
        "ac1": bytes([0, 0, 0, 2] + [0] * 12) + bytes([0x00, 0xF0]),
        "dc0": bytes([2] + [0] * 15) + bytes([0, 11]),
        "dc1": bytes([0] * 15 + [12]) + bytes(range(12)),
    }
    tables = dict(ANNEX_K)
    for name, payload in cases.items():
        await write_table(dut, name, payload)
        tables[name] = payload
    await commit(dut)
    assert cause(dut) == 0
    check_tables(await snapshot(dut), tables)
    await check_frame(dut, MODE_COLOUR, 20, 20, tables, rng)


@cocotb.test()
async def test_config_errors(dut):
    """BAD_CONFIG, ADDR_UNMAPPED, first-cause-kept, clear only when idle."""
    await reset(dut)
    rng = random.Random(18)
    # reset defaults: width and height are 0
    await cfg_write(dut, REG_CMD, 1)
    await RisingEdge(dut.clk)
    assert cause(dut) == E_CONFIG and dut.status_error.value == 1
    assert dut.status_idle.value == 1 and dut.out_valid.value == 0
    await clear_error(dut)

    await configure(dut, MODE_COLOUR, 0, 10)
    await cfg_write(dut, REG_CMD, 1)
    await RisingEdge(dut.clk)
    assert cause(dut) == E_CONFIG
    await clear_error(dut)
    await configure(dut, MODE_COLOUR, 10, 0)
    await cfg_write(dut, REG_CMD, 1)
    await RisingEdge(dut.clk)
    assert cause(dut) == E_CONFIG
    await clear_error(dut)
    for bad_mode in (3, 4, 255):
        await configure(dut, bad_mode, 10, 10)
        await cfg_write(dut, REG_CMD, 1)
        await RisingEdge(dut.clk)
        assert cause(dut) == E_CONFIG, bad_mode
        assert dut.status_idle.value == 1 and dut.out_valid.value == 0
        await clear_error(dut)
    for cmd in (0, 3, 5, 8, 255):
        await cfg_write(dut, REG_CMD, cmd)
        await RisingEdge(dut.clk)
        assert cause(dut) == E_CONFIG, cmd
        await clear_error(dut)

    snap0 = await snapshot(dut)
    for addr in (0x006, 0x03F, 0x0C0, 0x0FF, 0x11C, 0x13F, 0x1F2, 0x21C,
                 0x23F, 0x2F2, 0x300, 0x3FF, 0x400 - 1):
        await cfg_write(dut, addr, 0x55)
        await RisingEdge(dut.clk)
        assert cause(dut) == E_ADDR, hex(addr)
        await clear_error(dut)
    assert (await snapshot(dut)) == snap0, "unmapped writes changed memory"

    # first cause is kept
    await cfg_write(dut, 0x006, 1)
    await cfg_write(dut, REG_CMD, 9)
    await configure(dut, 3, 1, 1)
    await cfg_write(dut, REG_CMD, 1)
    await RisingEdge(dut.clk)
    assert cause(dut) == E_ADDR
    await clear_error(dut)
    assert dut.status_error.value == 0

    # the window edges are mapped
    for addr in (0x040, 0x07F, 0x080, 0x0BF, 0x100, 0x11B, 0x140, 0x1F1,
                 0x200, 0x21B, 0x240, 0x2F1):
        await cfg_write(dut, addr, 0x01)
        await RisingEdge(dut.clk)
        assert cause(dut) == 0, hex(addr)
    # restore defaults for hygiene
    await reset(dut)


@cocotb.test()
async def test_write_while_busy(dut):
    """Writes during a frame or a commit raise LOAD_WHILE_BUSY and change
    nothing; CMD=4 does not clear while busy."""
    await reset(dut)
    rng = random.Random(19)
    snap0 = await snapshot(dut)

    # during a frame: start, hold the scan back (header goes out, scan valid
    # low), then poke every kind of register / table / command
    got = bytearray()

    async def collect():
        while True:
            await RisingEdge(dut.clk)
            if dut.out_valid.value == 1 and dut.out_ready.value == 1:
                got.append(int(dut.out_data.value))
                if dut.out_last.value == 1:
                    return

    col = cocotb.start_soon(collect())
    await configure(dut, MODE_COLOUR, 64, 48)
    await cfg_write(dut, REG_CMD, 1)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.status_busy.value == 1 and dut.status_idle.value == 0
    mode0, w0, h0 = (int(dut.mode.value), int(dut.width.value), int(dut.height.value))
    pokes = [(REG_MODE, 1), (REG_W, 5), (REG_H, 7), (0x041, 0), (0x101, 3),
             (0x1F1, 9), (0x006, 1), (REG_CMD, 1), (REG_CMD, 2), (REG_CMD, 4)]
    for n, (addr, val) in enumerate(pokes):
        await cfg_write(dut, addr, val)
        await RisingEdge(dut.clk)
        assert cause(dut) == E_BUSY, f"poke {n} {hex(addr)}: cause {cause(dut)}"
        if addr == REG_CMD and val == 4:
            assert cause(dut) == E_BUSY, "CMD=4 must not clear while busy"
    assert (int(dut.mode.value), int(dut.width.value), int(dut.height.value)) == (mode0, w0, h0)
    # let the frame finish: drain the header, feed a scan, take the trailer
    scan = rand_scan(rng, 5)
    i = 0
    for _ in range(5000):
        dut.bp_valid.value = int(i < len(scan))
        if i < len(scan):
            dut.bp_data.value = scan[i]
            dut.bp_last.value = int(i == len(scan) - 1)
        await RisingEdge(dut.clk)
        if i < len(scan) and dut.bp_ready.value == 1:
            i += 1
        if col.done():
            break
    dut.bp_valid.value = 0
    assert col.done(), "frame did not finish"
    assert bytes(got) == ref_header(MODE_COLOUR, 64, 48, ANNEX_K) + scan + b"\xff\xd9"
    await wait_idle(dut)
    assert cause(dut) == E_BUSY            # sticky until cleared while idle
    await clear_error(dut)
    assert (await snapshot(dut)) == snap0, "busy-time writes changed memory"

    # during a commit
    new_ac1 = random_dht(random.Random(5), "ac1", 100)
    await write_table(dut, "ac1", new_ac1)
    await cfg_write(dut, REG_CMD, 2)
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert dut.status_busy.value == 1
    await cfg_write(dut, 0x241, 0xEE)
    await cfg_write(dut, REG_MODE, 2)
    await RisingEdge(dut.clk)
    assert cause(dut) == E_BUSY
    await wait_idle(dut)
    assert cause(dut) == E_BUSY
    tables = dict(ANNEX_K)
    tables["ac1"] = new_ac1
    check_tables(await snapshot(dut), tables)
    await clear_error(dut)
    assert int(dut.mode.value) == 0


@cocotb.test()
async def test_cfg_ready_only_during_rmw(dut):
    """cfg_ready is low only while a table word read-modify-write runs."""
    await reset(dut)
    # busy (commit) keeps cfg_ready high
    await cfg_write(dut, REG_CMD, 2)
    for _ in range(5):
        await RisingEdge(dut.clk)
        assert dut.cfg_ready.value == 1
    await wait_idle(dut)
    # a table byte write drops cfg_ready for the RMW, a register write does not
    dut.cfg_valid.value = 1
    dut.cfg_addr.value = 0x041
    dut.cfg_wdata.value = 7
    await RisingEdge(dut.clk)
    dut.cfg_valid.value = 0
    low = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        if dut.cfg_ready.value == 0:
            low += 1
    assert 0 < low < 20
    dut.cfg_valid.value = 1
    dut.cfg_addr.value = REG_MODE
    dut.cfg_wdata.value = 1
    await RisingEdge(dut.clk)
    dut.cfg_valid.value = 0
    await RisingEdge(dut.clk)
    assert dut.cfg_ready.value == 1
    # the byte landed in M1 word 186 + 0 (offset 1 -> lane 1)
    snap = await snapshot(dut)
    assert raw_bytes(snap, "q0", 2)[1] == 7
