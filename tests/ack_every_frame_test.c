/*
 * GAL_ACK_EVERY_FRAME: the player counts frames by the access unit delimiters
 * the hook appends, as the H.264 parser consumes them. Checks, on a real clip
 * fed in random-sized pieces, that the count never runs ahead of the access
 * units the parser has handed to the decoder (never ACK a frame not yet
 * decoded), that it has caught up whenever a piece ends on a delimiter, and
 * that every frame is counted once. Also that the parser hands each frame
 * over as soon as its delimiter arrives (the point of the delimiter).
 *
 * The counter is taken from player/opengl_gpu.cc itself (ack_counter.inc):
 *   sed -n '/^static bool g_ackEveryFrame = false;/,/^static void ack_settle(bool pictureWaiting);/p' \
 *       player/opengl_gpu.cc | grep -v '^static void ack_settle' > ack_counter.inc
 * Build against a host libavcodec (ffmpeg-mini configured for x86 with the
 * h264 parser and decoder) and run it on build/probe/test_1280x720.h264 and
 * tools/nvprobe/clip_800x480.h264.
 */
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libavcodec/avcodec.h>

#include "ack_counter.inc"

static uint8_t *load(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END); *n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *b = malloc(*n);
    if (fread(b, 1, *n, f) != *n) exit(2);
    fclose(f);
    return b;
}

int main(int argc, char **argv) {
    static const uint8_t aud[6] = {0, 0, 0, 1, 0x09, 0xf0};
    size_t n; uint8_t *clip = load(argv[1], &n);
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    AVPacket *pkt = av_packet_alloc();
    int fails = 0;

    /* 1. Cut the clip into access units as the phone sends them (no AUD). */
    AVCodecParserContext *p = av_parser_init(AV_CODEC_ID_H264);
    size_t cap = n * 2 + 4096, len = 0, frames = 0;
    uint8_t *stream = malloc(cap);
    const uint8_t *d = clip; size_t left = n;
    for (;;) {
        uint8_t *out; int outn;
        int used = av_parser_parse2(p, ctx, &out, &outn, d, (int)left, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
        d += used; left -= used;
        if (outn > 0) {
            memcpy(stream + len, out, outn); len += outn;
            memcpy(stream + len, aud, 6); len += 6;    /* what the hook adds */
            ++frames;
        }
        if (left == 0) {
            if (outn == 0 && used == 0) break;
            if (d == clip + n) { d = NULL; }   /* flush */
            if (!d) { av_parser_parse2(p, ctx, &out, &outn, NULL, 0, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
                      if (outn > 0) { memcpy(stream + len, out, outn); len += outn; memcpy(stream + len, aud, 6); len += 6; ++frames; }
                      break; }
        }
    }
    av_parser_close(p);
    printf("clip: %zu frames, %zu bytes with delimiters\n", frames, len);

    /* 2. Feed it as the player does, in random pieces. */
    for (int run = 0; run < 200; ++run) {
        srand(run);
        p = av_parser_init(AV_CODEC_ID_H264);
        g_ackEveryFrame = true; g_ackConsumed = 0; g_audZeros = 0;
        size_t pos = 0, out_units = 0;
        while (pos < len) {
            size_t piece = run == 0 ? len : 1 + (size_t)rand() % (run < 100 ? 64 : 40000);
            if (piece > len - pos) piece = len - pos;
            const uint8_t *data = stream + pos; size_t ds = piece;
            while (ds > 0) {
                uint8_t *out; int outn;
                int used = av_parser_parse2(p, ctx, &out, &outn, data, (int)ds, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
                if (used < 0) { printf("parse error\n"); return 1; }
                ack_count_bytes(data, (size_t)used);
                data += used; ds -= used;
                if (outn > 0) ++out_units;
                if (g_ackConsumed > out_units) {
                    if (fails++ < 5) printf("run %d: counted %llu frames, only %zu handed to the decoder\n",
                                            run, (unsigned long long)g_ackConsumed, out_units);
                }
            }
            pos += piece;
            /* A piece ending right after a delimiter: that frame is with the
             * decoder now, and counted. */
            if (pos >= 6 && memcmp(stream + pos - 6, aud, 6) == 0 &&
                (out_units != g_ackConsumed)) {
                if (fails++ < 5) printf("run %d: piece ends on a delimiter, %zu handed over, %llu counted\n",
                                        run, out_units, (unsigned long long)g_ackConsumed);
            }
        }
        if (g_ackConsumed != frames || out_units != frames) {
            if (fails++ < 5) printf("run %d: %zu frames, %zu handed over, %llu counted\n",
                                    run, frames, out_units, (unsigned long long)g_ackConsumed);
        }
        av_parser_close(p);
    }
    printf(fails ? "FAIL (%d)\n" : "ok: 200 runs, every frame counted once, never ahead of the decoder\n", fails);
    return fails != 0;
}
