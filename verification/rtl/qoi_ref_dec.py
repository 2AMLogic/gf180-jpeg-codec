"""Shared runner for the vendored QOI reference decoder (issue #245).

Both the QOI stage bench and the top-level smoke bench decode with the same
reference (`qoi_dec_ref.c`, built on the vendored qoi.h). A test owns a
temporary directory, compiles the decoder into it once and reuses the
executable for every image. The stage bench wraps the DUT's chunk stream in
the QOI header and end marker itself; the smoke bench passes the DUT's
complete output unchanged. decode() returns the decoder's exit status so a
corruption control can require a pixel mismatch, not just a pass.
"""

import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "golden", "ref")


class QoiRefDec:
    """The reference decoder, compiled once into a caller-owned directory."""

    def __init__(self, tmpdir):
        self.tmpdir = tmpdir
        self.exe = os.path.join(tmpdir, "qoi_dec_ref")
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-Wall", "-I", REF,
                        "-o", self.exe, os.path.join(HERE, "qoi_dec_ref.c")],
                       check=True)
        self._case = 0

    def decode(self, qoi_bytes, rgb_bytes, w, h):
        """Decode one QOI file against expected RGB; returns the exit status."""
        self._case += 1
        qp = os.path.join(self.tmpdir, "case%d.qoi" % self._case)
        rp = os.path.join(self.tmpdir, "case%d.rgb" % self._case)
        with open(qp, "wb") as f:
            f.write(bytes(qoi_bytes))
        with open(rp, "wb") as f:
            f.write(bytes(rgb_bytes))
        return subprocess.run([self.exe, qp, rp, str(w), str(h)]).returncode
