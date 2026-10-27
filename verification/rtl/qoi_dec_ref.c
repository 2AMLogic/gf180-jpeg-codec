/* Decode check around the vendored qoi.h (used by test_qoi.py).
 *
 *   qoi_dec_ref <in.qoi> <expected.rgb> <width> <height>
 *
 * Decodes in.qoi with qoi_decode (3 channels) and exits non-zero unless the
 * header reports width x height, 3 channels, colourspace 0 and the pixels
 * equal the raw RGB bytes in expected.rgb.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define QOI_IMPLEMENTATION
#include "qoi.h"

static unsigned char *slurp(const char *path, long *len) {
	FILE *f = fopen(path, "rb");
	unsigned char *buf;
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	*len = ftell(f);
	fseek(f, 0, SEEK_SET);
	buf = malloc(*len ? *len : 1);
	if (!buf || fread(buf, 1, *len, f) != (size_t)*len) { fclose(f); return NULL; }
	fclose(f);
	return buf;
}

int main(int argc, char **argv) {
	long qlen, elen;
	unsigned char *q, *exp, *dec;
	qoi_desc d;
	unsigned int w, h;

	if (argc != 5) { fprintf(stderr, "usage: qoi_dec_ref in.qoi exp.rgb w h\n"); return 2; }
	w = (unsigned)atoi(argv[3]);
	h = (unsigned)atoi(argv[4]);
	q = slurp(argv[1], &qlen);
	exp = slurp(argv[2], &elen);
	if (!q || !exp || elen != (long)(w * h * 3)) { fprintf(stderr, "qoi_dec_ref: bad input\n"); return 2; }
	dec = qoi_decode(q, (int)qlen, &d, 3);
	if (!dec) { fprintf(stderr, "qoi_dec_ref: decode failed\n"); return 1; }
	if (d.width != w || d.height != h || d.channels != 3 || d.colorspace != QOI_SRGB) {
		fprintf(stderr, "qoi_dec_ref: header mismatch\n");
		return 1;
	}
	if (memcmp(dec, exp, elen) != 0) { fprintf(stderr, "qoi_dec_ref: pixels differ\n"); return 1; }
	return 0;
}
