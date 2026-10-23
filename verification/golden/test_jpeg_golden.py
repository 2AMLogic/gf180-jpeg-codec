"""Unit tests for jpeg_golden.py.

Run: python3 -m unittest discover -s verification/golden -p 'test_*.py'
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jpeg_golden as g  # noqa: E402

# Spec codec.md section 5 / record 0003 worked-example block.
BLOCK = [
    52, 55, 61, 66, 70, 61, 64, 73,
    63, 59, 55, 90, 109, 85, 69, 72,
    62, 59, 68, 113, 144, 104, 66, 73,
    63, 58, 71, 122, 154, 106, 70, 69,
    67, 61, 68, 104, 126, 88, 68, 70,
    79, 65, 60, 70, 77, 68, 58, 75,
    85, 71, 64, 59, 55, 61, 65, 83,
    87, 79, 69, 68, 65, 76, 78, 94,
]


class TestBlock(unittest.TestCase):
    def test_pass1_row_example(self):
        row = [s - 128 for s in BLOCK[0:8]]
        self.assertEqual(g._fdct_1d(row, 1),
                         [-2088, -163, -64, -76, 80, -35, -8, 27])

    def test_dct_first_two_rows(self):
        c = g.fdct_block(BLOCK)
        self.assertEqual(c[0:8], [-3323, -241, -489, 218, 449, -160, -19, 4])
        self.assertEqual(c[8:16], [36, -174, -486, 82, 105, -57, -68, 39])

    def test_flat_blocks(self):
        self.assertEqual(g.fdct_block([255] * 64), [8128] + [0] * 63)
        self.assertEqual(g.fdct_block([0] * 64), [-8192] + [0] * 63)

    def test_quantized_example_rows(self):
        qnat = g.zigzag_to_natural(g.ANNEX_K_LUMA_QUANT_ZZ)
        q = g.dct_quantize_block(BLOCK, qnat)
        self.assertEqual(q[0:8], [-26, -3, -6, 2, 2, -1, 0, 0])
        self.assertEqual(q[8:16], [0, -2, -4, 1, 1, 0, 0, 0])

    def test_scan_of_example_block(self):
        qz = g.ANNEX_K_LUMA_QUANT_ZZ
        jpg = g.encode(bytes(BLOCK), 8, 8, "grey", qz, qz)
        self.assertEqual(g.scan_bytes(jpg).hex(), "c54d8b0b4650994b021bd057")


class TestQuantizer(unittest.TestCase):
    def test_clamp_counted(self):
        stats = {}
        coefs = [0] * 64
        coefs[0] = 8128
        coefs[1] = 8192   # Q=1: 1024 -> clamped to 1023
        coefs[2] = -8192
        out = g.quantize_block(coefs, [1] * 64, stats)
        self.assertEqual((out[0], out[1], out[2]), (1016, 1023, -1023))
        self.assertEqual(stats["ac_clamps"], 2)

    def test_round_half_away_from_zero(self):
        c = [0] * 64
        c[1], c[2] = 4, -4          # D = 8: |x| = D/2 rounds up to 1
        c[3], c[4] = 3, -3          # below half rounds to 0
        out = g.quantize_block(c, [1] * 64)
        self.assertEqual(out[1:5], [1, -1, 0, 0])

    def test_zero_q_rejected(self):
        z = [1] * 64
        z[5] = 0
        with self.assertRaises(ValueError):
            g.encode(bytes(64), 8, 8, "grey", z, z)

    def test_quality_tables(self):
        lum, _ = g.quality_tables(50)
        self.assertEqual(lum, list(g.ANNEX_K_LUMA_QUANT_ZZ))
        lum, _ = g.quality_tables(100)
        self.assertEqual(set(lum), {1})


class TestEncode(unittest.TestCase):
    def test_flat_is_dc_only_and_framed(self):
        qz = g.ANNEX_K_LUMA_QUANT_ZZ
        jpg = g.encode(bytes([128] * 64), 8, 8, "grey", qz, qz)
        self.assertEqual(jpg[:2], b"\xff\xd8")
        self.assertEqual(jpg[-2:], b"\xff\xd9")
        # DC diff 0 (size 0, code 00) then EOB (1010), padded with ones.
        self.assertEqual(g.scan_bytes(jpg), bytes([0b00101011]))

    def test_stuffing(self):
        x = 0x1BADB002
        px = bytearray()
        for _ in range(16 * 16 * 3):
            x ^= (x << 13) & 0xFFFFFFFF
            x ^= x >> 17
            x ^= (x << 5) & 0xFFFFFFFF
            px.append(x >> 24)
        lq, cq = g.quality_tables(95)
        scan = g.scan_bytes(g.encode(bytes(px), 16, 16, "colour", lq, cq))
        self.assertIn(b"\xff\x00", scan)
        for i, b in enumerate(scan[:-1]):
            if b == 0xFF:
                self.assertEqual(scan[i + 1], 0)

    def test_padding_non_multiple(self):
        lq, cq = g.quality_tables(75)
        g.encode(bytes(100 * 60), 100, 60, "grey", lq, cq)
        g.encode(bytes(30 * 17 * 3), 30, 17, "colour", lq, cq)


if __name__ == "__main__":
    unittest.main()
