/* Reference harness around the vendored qoi.h (see qoi_crosscheck.py).
 *
 *   qoi_ref <in.ppm> <out.qoi>
 *
 * Reads a binary P6 PPM (maxval 255), encodes it with qoi_encode (3 channels,
 * colourspace 0), writes the .qoi, then decodes it with qoi_decode and exits
 * non-zero unless the decoded pixels equal the input exactly.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define QOI_IMPLEMENTATION
#include "qoi.h"

int main(int argc, char **argv) {
	FILE *f;
	unsigned int w, h, maxv;
	unsigned char *px, *dec;
	void *enc;
	int n, enc_len;
	qoi_desc desc, ddesc;

	if (argc != 3) {
		fprintf(stderr, "usage: qoi_ref in.ppm out.qoi\n");
		return 2;
	}
	f = fopen(argv[1], "rb");
	if (!f || fscanf(f, "P6 %u %u %u", &w, &h, &maxv) != 3 || maxv != 255 || fgetc(f) == EOF) {
		fprintf(stderr, "qoi_ref: bad PPM %s\n", argv[1]);
		return 2;
	}
	n = (int)(w * h * 3);
	px = malloc(n);
	if (!px || fread(px, 1, n, f) != (size_t)n) {
		fprintf(stderr, "qoi_ref: short PPM %s\n", argv[1]);
		return 2;
	}
	fclose(f);

	desc.width = w; desc.height = h; desc.channels = 3; desc.colorspace = QOI_SRGB;
	enc = qoi_encode(px, &desc, &enc_len);
	if (!enc) { fprintf(stderr, "qoi_ref: encode failed\n"); return 1; }

	f = fopen(argv[2], "wb");
	if (!f || fwrite(enc, 1, enc_len, f) != (size_t)enc_len) { fprintf(stderr, "qoi_ref: write failed\n"); return 2; }
	fclose(f);

	dec = qoi_decode(enc, enc_len, &ddesc, 3);
	if (!dec || ddesc.width != w || ddesc.height != h || memcmp(dec, px, n) != 0) {
		fprintf(stderr, "qoi_ref: decode does not reproduce the input: %s\n", argv[1]);
		return 1;
	}
	return 0;
}
