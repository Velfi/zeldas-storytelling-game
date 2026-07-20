#include <stdlib.h>

extern int stb_vorbis_decode_filename(
    const char *filename,
    int *channels,
    int *sample_rate,
    short **output);

void chicago_vorbis_free(short *samples) {
    free(samples);
}
