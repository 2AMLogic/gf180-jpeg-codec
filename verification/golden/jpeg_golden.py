"""Golden baseline-JPEG encoder: integer-only, standard library only.

Implements spec/codec.md sections 2 to 7 with the arithmetic of decision
record 0003 (jfdctint "islow" DCT).  RTL output must equal this model byte
for byte; libjpeg-turbo (via Pillow) is the independent check beside it
(crosscheck_libjpeg.py), not a substitute.

Conventions: ">>" is an arithmetic (floor) shift, "//" is floor division, and
no value here is ever anything but a Python int.  Tables are held in
DQT/DHT payload (zig-zag) order unless a name says "natural".
"""

# T.81 Figure A.6: natural index (row*8 + column) of each zig-zag position.
ZIGZAG = (
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
)

# T.81 Annex K.1 (quantization, zig-zag order) and K.3 (Huffman BITS/HUFFVAL).
# Copied from the DQT/DHT segments of a libjpeg-turbo 2.1.5 file at quality
# 50; crosscheck_libjpeg.py re-checks them on every run through the scan bytes.
ANNEX_K_LUMA_QUANT_ZZ = (
    16, 11, 12, 14, 12, 10, 16, 14, 13, 14, 18, 17, 16, 19, 24, 40, 26, 24,
    22, 22, 24, 49, 35, 37, 29, 40, 58, 51, 61, 60, 57, 51, 56, 55, 64, 72,
    92, 78, 64, 68, 87, 69, 55, 56, 80, 109, 81, 87, 95, 98, 103, 104, 103,
    62, 77, 113, 121, 112, 100, 120, 92, 101, 103, 99,
)

ANNEX_K_CHROMA_QUANT_ZZ = (
    17, 18, 18, 24, 21, 24, 47, 26, 26, 47, 99, 66, 56, 66, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
)

ANNEX_K_DC_LUMA_BITS = (
    0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
)

ANNEX_K_DC_LUMA_VALS = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
)

ANNEX_K_AC_LUMA_BITS = (
    0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125,
)

ANNEX_K_AC_LUMA_VALS = (
    1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7, 34, 113, 20, 50,
    129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114,
    130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40, 41, 42, 52, 53, 54, 55,
    56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89,
    90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120,
    121, 122, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148, 149,
    150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170,
    178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198,
    199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225,
    226, 227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244, 245,
    246, 247, 248, 249, 250,
)

ANNEX_K_DC_CHROMA_BITS = (
    0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
)

ANNEX_K_DC_CHROMA_VALS = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
)

ANNEX_K_AC_CHROMA_BITS = (
    0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119,
)

ANNEX_K_AC_CHROMA_VALS = (
    0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50,
    129, 8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114,
    209, 10, 22, 36, 52, 225, 37, 241, 23, 24, 25, 26, 38, 39, 40, 41, 42,
    53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86,
    87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117,
    118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136, 137, 138,
    146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166,
    167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194,
    195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215,
    216, 217, 218, 226, 227, 228, 229, 230, 231, 232, 233, 234, 242, 243,
    244, 245, 246, 247, 248, 249, 250,
)

# Record 0003 constants.
CONST_BITS = 13
PASS1_BITS = 2
FIX_0_298631336 = 2446
FIX_0_390180644 = 3196
FIX_0_541196100 = 4433
FIX_0_765366865 = 6270
FIX_0_899976223 = 7373
FIX_1_175875602 = 9633
FIX_1_501321110 = 12299
FIX_1_847759065 = 15137
FIX_1_961570560 = 16069
FIX_2_053119869 = 16819
FIX_2_562915447 = 20995
FIX_3_072711026 = 25172

AC_CLAMP = 1023  # spec section 5: largest magnitude of size category 10


def descale(x, n):
    return (x + (1 << (n - 1))) >> n


def quality_tables(quality):
    """Annex K tables scaled as libjpeg's jpeg_set_quality (baseline-forced)."""
    quality = max(1, min(100, quality))
    scale = 5000 // quality if quality < 50 else 200 - quality * 2

    def one(base):
        return [max(1, min(255, (v * scale + 50) // 100)) for v in base]

    return one(ANNEX_K_LUMA_QUANT_ZZ), one(ANNEX_K_CHROMA_QUANT_ZZ)


def zigzag_to_natural(zz):
    nat = [0] * 64
    for k in range(64):
        nat[ZIGZAG[k]] = zz[k]
    return nat


# ---------------------------------------------------------------- colour --

def rgb_to_ycc(r, g, b):
    """Spec section 4 (jccolor.c, SCALEBITS = 16); no saturation needed."""
    y = (19595 * r + 38470 * g + 7471 * b + 32768) >> 16
    cb = (-11059 * r - 21709 * g + 32768 * b + (128 << 16) + 32768 - 1) >> 16
    cr = (32768 * r - 27439 * g - 5329 * b + (128 << 16) + 32768 - 1) >> 16
    return y, cb, cr


def _pad_plane(plane, w, h, pw, ph):
    """Replicate the last column and last row up to (pw, ph) (spec section 2)."""
    rows = []
    for y in range(ph):
        src = plane[min(y, h - 1) * w:min(y, h - 1) * w + w]
        rows.extend(src + [src[-1]] * (pw - w))
    return rows


def _downsample_420(plane, pw, ph):
    """h2v2_downsample, smoothing off: bias 1 on even output columns, 2 on odd."""
    out = []
    for y in range(0, ph, 2):
        for j in range(pw // 2):
            i = 2 * j
            s = (plane[y * pw + i] + plane[y * pw + i + 1]
                 + plane[(y + 1) * pw + i] + plane[(y + 1) * pw + i + 1])
            out.append((s + (1 if j % 2 == 0 else 2)) >> 2)
    return out


# ------------------------------------------------------------------- DCT --

def _fdct_1d(d, pass_no):
    """One 8-point pass of record 0003; pass_no is 1 (rows) or 2 (columns)."""
    s = CONST_BITS - PASS1_BITS if pass_no == 1 else CONST_BITS + PASS1_BITS
    t0 = d[0] + d[7]
    t7 = d[0] - d[7]
    t1 = d[1] + d[6]
    t6 = d[1] - d[6]
    t2 = d[2] + d[5]
    t5 = d[2] - d[5]
    t3 = d[3] + d[4]
    t4 = d[3] - d[4]

    t10 = t0 + t3
    t13 = t0 - t3
    t11 = t1 + t2
    t12 = t1 - t2

    o = [0] * 8
    if pass_no == 1:
        o[0] = (t10 + t11) << PASS1_BITS
        o[4] = (t10 - t11) << PASS1_BITS
    else:
        o[0] = descale(t10 + t11, PASS1_BITS)
        o[4] = descale(t10 - t11, PASS1_BITS)

    z1 = (t12 + t13) * FIX_0_541196100
    o[2] = descale(z1 + t13 * FIX_0_765366865, s)
    o[6] = descale(z1 + t12 * -FIX_1_847759065, s)

    z1 = t4 + t7
    z2 = t5 + t6
    z3 = t4 + t6
    z4 = t5 + t7
    z5 = (z3 + z4) * FIX_1_175875602
    t4 *= FIX_0_298631336
    t5 *= FIX_2_053119869
    t6 *= FIX_3_072711026
    t7 *= FIX_1_501321110
    z1 *= -FIX_0_899976223
    z2 *= -FIX_2_562915447
    z3 *= -FIX_1_961570560
    z4 *= -FIX_0_390180644
    z3 += z5
    z4 += z5

    o[7] = descale(t4 + z1 + z3, s)
    o[5] = descale(t5 + z2 + z4, s)
    o[3] = descale(t6 + z2 + z3, s)
    o[1] = descale(t7 + z1 + z4, s)
    return o


def fdct_block(samples):
    """8x8 samples (0..255, row-major) -> 8x the orthonormal DCT, row-major."""
    ws = [0] * 64
    for r in range(8):
        row = _fdct_1d([samples[r * 8 + c] - 128 for c in range(8)], 1)
        ws[r * 8:r * 8 + 8] = row
    out = [0] * 64
    for c in range(8):
        col = _fdct_1d([ws[r * 8 + c] for r in range(8)], 2)
        for r in range(8):
            out[r * 8 + c] = col[r]
    return out


def quantize_block(coefs, q_natural, stats=None, round_delta=0):
    """Spec section 5: D = 8*Q, round half away from zero, AC clamp +-1023.

    round_delta is the negative-control hook: it perturbs the rounding
    constant (D >> 1); production callers leave it 0.
    """
    out = [0] * 64
    for i in range(64):
        x = coefs[i]
        d = 8 * q_natural[i]
        mag = (abs(x) + (d >> 1) + round_delta) // d
        q = -mag if x < 0 else mag
        if i != 0 and (q > AC_CLAMP or q < -AC_CLAMP):
            q = AC_CLAMP if q > 0 else -AC_CLAMP
            if stats is not None:
                stats["ac_clamps"] = stats.get("ac_clamps", 0) + 1
        out[i] = q
    return out


def dct_quantize_block(samples, q_natural, stats=None, round_delta=0):
    return quantize_block(fdct_block(samples), q_natural, stats, round_delta)


# --------------------------------------------------------------- entropy --

def build_codes(bits, vals):
    """T.81 Annex C canonical codes: symbol -> (code, length)."""
    codes = {}
    code = 0
    k = 0
    for length in range(1, 17):
        for _ in range(bits[length - 1]):
            codes[vals[k]] = (code, length)
            code += 1
            k += 1
        code <<= 1
    return codes


class _BitWriter:
    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, code, length):
        if length == 0:
            return
        self.acc = (self.acc << length) | (code & ((1 << length) - 1))
        self.n += length
        while self.n >= 8:
            self.n -= 8
            byte = (self.acc >> self.n) & 0xFF
            self.out.append(byte)
            if byte == 0xFF:
                self.out.append(0x00)
        self.acc &= (1 << self.n) - 1

    def finish(self):
        if self.n:
            self.put((1 << (8 - self.n)) - 1, 8 - self.n)
        return bytes(self.out)


def _encode_block(bw, qnat, pred, dc_codes, ac_codes):
    zz = [qnat[ZIGZAG[k]] for k in range(64)]
    diff = zz[0] - pred
    size = abs(diff).bit_length()
    bw.put(*dc_codes[size])
    bw.put(diff if diff >= 0 else diff + (1 << size) - 1, size)
    run = 0
    for k in range(1, 64):
        v = zz[k]
        if v == 0:
            run += 1
            continue
        while run >= 16:
            bw.put(*ac_codes[0xF0])
            run -= 16
        size = abs(v).bit_length()
        bw.put(*ac_codes[(run << 4) | size])
        bw.put(v if v >= 0 else v + (1 << size) - 1, size)
        run = 0
    if run:
        bw.put(*ac_codes[0x00])
    return zz[0]


# --------------------------------------------------------------- framing --

def _segment(marker, payload):
    return bytes([0xFF, marker]) + (len(payload) + 2).to_bytes(2, "big") + bytes(payload)


def _header(width, height, mode, q_luma, q_chroma):
    colour = mode == "colour"
    out = bytearray(b"\xff\xd8")
    out += _segment(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00")
    out += _segment(0xDB, bytes([0]) + bytes(q_luma))
    if colour:
        out += _segment(0xDB, bytes([1]) + bytes(q_chroma))
    comps = ([(1, 0x22, 0), (2, 0x11, 1), (3, 0x11, 1)] if colour
             else [(1, 0x11, 0)])
    sof = bytearray([8]) + height.to_bytes(2, "big") + width.to_bytes(2, "big")
    sof.append(len(comps))
    for cid, samp, tq in comps:
        sof += bytes([cid, samp, tq])
    out += _segment(0xC0, sof)
    tables = [(0x00, ANNEX_K_DC_LUMA_BITS, ANNEX_K_DC_LUMA_VALS),
              (0x10, ANNEX_K_AC_LUMA_BITS, ANNEX_K_AC_LUMA_VALS)]
    if colour:
        tables += [(0x01, ANNEX_K_DC_CHROMA_BITS, ANNEX_K_DC_CHROMA_VALS),
                   (0x11, ANNEX_K_AC_CHROMA_BITS, ANNEX_K_AC_CHROMA_VALS)]
    for tcth, bits, vals in tables:
        out += _segment(0xC4, bytes([tcth]) + bytes(bits) + bytes(vals))
    sos = bytearray([len(comps)])
    for cid, td_ta in ([(1, 0x00), (2, 0x11), (3, 0x11)] if colour else [(1, 0x00)]):
        sos += bytes([cid, td_ta])
    sos += bytes([0, 63, 0])
    out += _segment(0xDA, sos)
    return bytes(out)


def encode(pixels, width, height, mode, q_luma, q_chroma, stats=None,
           round_delta=0):
    """Encode one frame to a complete JFIF file.

    pixels: R,G,B bytes in image raster order (mode "colour") or luma bytes
    (mode "grey"); the model pads to a whole MCU by edge replication.
    q_luma, q_chroma: 64 entries in DQT (zig-zag) order, each 1..255
    (q_chroma is ignored in grey mode).  stats, if given, receives the AC
    clamp count under "ac_clamps".
    """
    if mode not in ("colour", "grey"):
        raise ValueError("mode must be 'colour' or 'grey'")
    if not (1 <= width <= 65535 and 1 <= height <= 65535):
        raise ValueError("size out of range")
    for t in (q_luma,) + ((q_chroma,) if mode == "colour" else ()):
        if len(t) != 64 or any(not 1 <= v <= 255 for v in t):
            raise ValueError("quantization entries must be 64 values in 1..255")
    colour = mode == "colour"
    if len(pixels) != width * height * (3 if colour else 1):
        raise ValueError("pixel count does not match size and mode")
    if stats is not None:
        stats.setdefault("ac_clamps", 0)

    mcu = 16 if colour else 8
    pw = -(-width // mcu) * mcu
    ph = -(-height // mcu) * mcu
    if colour:
        yp, cbp, crp = [], [], []
        for i in range(width * height):
            y, cb, cr = rgb_to_ycc(pixels[3 * i], pixels[3 * i + 1], pixels[3 * i + 2])
            yp.append(y)
            cbp.append(cb)
            crp.append(cr)
        planes = [_pad_plane(p, width, height, pw, ph) for p in (yp, cbp, crp)]
        cb_sub = _downsample_420(planes[1], pw, ph)
        cr_sub = _downsample_420(planes[2], pw, ph)
    else:
        planes = [_pad_plane(list(pixels), width, height, pw, ph)]

    qy = zigzag_to_natural(q_luma)
    qc = zigzag_to_natural(q_chroma) if colour else None
    dc_l = build_codes(ANNEX_K_DC_LUMA_BITS, ANNEX_K_DC_LUMA_VALS)
    ac_l = build_codes(ANNEX_K_AC_LUMA_BITS, ANNEX_K_AC_LUMA_VALS)
    dc_c = build_codes(ANNEX_K_DC_CHROMA_BITS, ANNEX_K_DC_CHROMA_VALS)
    ac_c = build_codes(ANNEX_K_AC_CHROMA_BITS, ANNEX_K_AC_CHROMA_VALS)

    def block(plane, stride, bx, by):
        return [plane[(by + r) * stride + bx + c] for r in range(8) for c in range(8)]

    bw = _BitWriter()
    pred = [0, 0, 0]
    if colour:
        for my in range(ph // 16):
            for mx in range(pw // 16):
                for (r, c) in ((0, 0), (0, 1), (1, 0), (1, 1)):
                    q = dct_quantize_block(
                        block(planes[0], pw, mx * 16 + c * 8, my * 16 + r * 8),
                        qy, stats, round_delta)
                    pred[0] = _encode_block(bw, q, pred[0], dc_l, ac_l)
                for ci, sub in ((1, cb_sub), (2, cr_sub)):
                    q = dct_quantize_block(block(sub, pw // 2, mx * 8, my * 8),
                                           qc, stats, round_delta)
                    pred[ci] = _encode_block(bw, q, pred[ci], dc_c, ac_c)
    else:
        for by in range(ph // 8):
            for bx in range(pw // 8):
                q = dct_quantize_block(block(planes[0], pw, bx * 8, by * 8),
                                       qy, stats, round_delta)
                pred[0] = _encode_block(bw, q, pred[0], dc_l, ac_l)
    return _header(width, height, mode, q_luma, q_chroma) + bw.finish() + b"\xff\xd9"


def scan_bytes(jpeg):
    """Entropy-coded segment: the bytes after the SOS header up to EOI."""
    i = 2
    while i < len(jpeg):
        if jpeg[i] != 0xFF:
            raise ValueError("lost marker sync at offset %d" % i)
        marker = jpeg[i + 1]
        length = int.from_bytes(jpeg[i + 2:i + 4], "big")
        i += 2 + length
        if marker == 0xDA:
            break
    if jpeg[-2:] != b"\xff\xd9":
        raise ValueError("missing EOI")
    return jpeg[i:-2]
