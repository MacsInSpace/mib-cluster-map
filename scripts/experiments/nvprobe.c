/*
 * nvprobe: can the unit's Tegra H.264 decoder be used without a display
 * output?  An experiment, not part of the package.
 *
 * The player's hardware path (libnvss_video.so) decodes and draws straight to
 * a display output.  On VW and Skoda the cockpit is not such an output (0x0),
 * so it fails there.  libnvss_video.so itself sits on two lower libraries:
 * libnvparser.so (H.264 parser with callbacks) and libnvmedia.so (decoder and
 * picture surfaces).  This program uses those two the way libnvss_video.so
 * does, minus the mixer and the output: parse a file, decode every picture
 * into a surface, lock the surface and look at the bytes.
 *
 * Every offset below was read from libnvss_video.so of MHI2_ER_VWG13_P4521
 * (its BeginSequence at 0x46a0, DecodePicture at 0x506c, decoder set-up at
 * 0x411c).  Nothing is assumed from headers.
 *
 *   nvprobe <file.h264> <log file> [max pictures]
 *
 * Result on a Golf MHI2_ER_VWG13_P4521, 2026-11-17 (probe 1): it works.
 *   800x480:  300 of 300 pictures, 115 a second, 3.1 ms of processor time a
 *             picture (parse, decode call, lock, luma copy): about 9 % of one
 *             core at 30 a second.  The software decoder uses a whole core.
 *   1280x720: 150 of 150, 57 a second, 7 ms a picture.
 *   The pixels match a reference decode of the same clips exactly.
 *   Lock map: {width, height, Y, Y pitch, plane, pitch, plane, pitch};
 *   the Y pitch of an 800 wide picture is 832, chroma 448.  Probe 1 took the
 *   pitch from the wrong word (the width); fixed below.
 *   Not shown yet: running beside gal's own decoder for the centre screen
 *   (the green menu was in front, so that decoder was stopped).
 */
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int g_log = -1;
static const char *g_stage = "start";

static void logf_(const char *fmt, ...)
{
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(b, sizeof(b) - 1, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if (n > (int)sizeof(b) - 2) n = sizeof(b) - 2;
    b[n++] = '\n';
    if (g_log >= 0) { write(g_log, b, n); fsync(g_log); }
    write(1, b, n);
}

static void on_signal(int sig)
{
    char b[160];
    int n = snprintf(b, sizeof(b), "STOPPED by signal %d at stage: %s\n", sig, g_stage);
    if (g_log >= 0) { write(g_log, b, n); fsync(g_log); }
    write(1, b, n);
    _exit(3);
}

static double now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static uint32_t rd32(const void *p, unsigned off) { uint32_t v; memcpy(&v, (const uint8_t *)p + off, 4); return v; }
static uint16_t rd16(const void *p, unsigned off) { uint16_t v; memcpy(&v, (const uint8_t *)p + off, 2); return v; }
static uint8_t  rd8(const void *p, unsigned off) { return ((const uint8_t *)p)[off]; }
static void wr32(void *p, unsigned off, uint32_t v) { memcpy((uint8_t *)p + off, &v, 4); }
static void wr16(void *p, unsigned off, uint16_t v) { memcpy((uint8_t *)p + off, &v, 2); }
static void wr8(void *p, unsigned off, uint8_t v) { ((uint8_t *)p)[off] = v; }

/* The functions, found at run time so a missing one is a log line. */
static void *(*NvMediaDeviceCreate)(void);
static void  (*NvMediaDeviceDestroy)(void *);
static void *(*NvMediaVideoDecoderCreate)(int codec, uint16_t w, uint16_t h, uint16_t refs, uint32_t maxBitstream, uint32_t inputBuffering);
static void  (*NvMediaVideoDecoderDestroy)(void *);
static int   (*NvMediaVideoDecoderRender)(void *dec, void *target, const void *picInfo, uint32_t nBuffers, const void *buffers);
static void *(*NvMediaVideoSurfaceCreate)(void *dev, int type, uint16_t w, uint16_t h);
static void  (*NvMediaVideoSurfaceDestroy)(void *);
static int   (*NvMediaVideoSurfaceLock)(void *surface, void *map);
static void  (*NvMediaVideoSurfaceUnlock)(void *surface);
static void *(*video_parser_create)(void *params);
static void  (*video_parser_destroy)(void *);
static int   (*video_parser_parse)(void *parser, void *packet);
static int   (*video_parser_set_attribute)(void *parser, int attr, int size, void *value);

#define MAX_PICS 24
typedef struct { void *surface; int refs; int index; } Pic;   /* what the parser carries around as its picture buffer */

static void *g_device, *g_decoder;
static Pic g_pics[MAX_PICS];
static int g_nPics;
static unsigned g_w, g_h;
static int g_devnull = -1;
static unsigned g_decoded, g_shown, g_renderFail, g_lockFail, g_maxPictures = 100000;
static double g_renderMs, g_renderMax, g_lockMs, g_copyMs;
static unsigned g_locks, g_copies;
static uint8_t *g_copyBuf;
static int g_yWord = -1;        /* which word of the lock map points at the luma plane, once found */
static int g_pitchWord = -1;

static int readable(const void *p, size_t n)
{
    /* A bad address makes write() fail with EFAULT instead of ending us. */
    if (g_devnull < 0 || (uintptr_t)p < 0x10000) return 0;
    if (write(g_devnull, p, 1) != 1) return 0;
    if (n > 1 && write(g_devnull, (const uint8_t *)p + n - 1, 1) != 1) return 0;
    return 1;
}

static int cb_begin(void *ctx, const void *seq)
{
    (void)ctx;
    g_stage = "BeginSequence";
    int codec = (int)rd32(seq, 0x00);
    int nBuf = (int)rd32(seq, 0x10);
    unsigned dw = rd32(seq, 0x18), dh = rd32(seq, 0x1c);
    unsigned w = rd32(seq, 0x20), h = rd32(seq, 0x24);
    unsigned chroma = rd8(seq, 0x30);
    uint32_t maxBs = rd32(seq, 0x58);
    logf_("sequence: codec=%d decodeBuffers=%d display=%ux%u coded=%ux%u chroma=%u maxBitstream=%u",
          codec, nBuf, dw, dh, w, h, chroma, (unsigned)maxBs);
    {
        char line[400]; int n = 0; unsigned i;
        for (i = 0; i < 0x60; i += 4) n += snprintf(line + n, sizeof(line) - n, "%08x ", (unsigned)rd32(seq, i));
        logf_("sequence words: %s", line);
    }
    if (codec != 4) { logf_("sequence: not H.264 for the parser (want 4)"); return 0; }
    if (g_decoder && w == g_w && h == g_h) return nBuf;
    if (g_decoder) { logf_("sequence: size changed; the probe keeps to the first size"); return 0; }
    g_w = w; g_h = h;

    uint16_t refs = 0;
    if (nBuf > 0) { int r = nBuf - 1; if (r > 16) r = 16; refs = (uint16_t)r; }
    g_stage = "NvMediaVideoDecoderCreate";
    double t = now_ms();
    g_decoder = NvMediaVideoDecoderCreate(0, (uint16_t)w, (uint16_t)h, refs, maxBs, 3);
    logf_("decoder: NvMediaVideoDecoderCreate(H264, %ux%u, refs=%u, maxBitstream=%u, 3) = %p in %.1f ms",
          w, h, refs, (unsigned)maxBs, g_decoder, now_ms() - t);
    if (!g_decoder) return 0;

    int type = chroma <= 1 ? 0 : (chroma == 2 ? 1 : 2);
    int want = nBuf + 3; if (want > MAX_PICS) want = MAX_PICS; if (want < 4) want = 4;
    g_stage = "NvMediaVideoSurfaceCreate";
    for (g_nPics = 0; g_nPics < want; g_nPics++) {
        void *s = NvMediaVideoSurfaceCreate(g_device, type, (uint16_t)((w + 15) & 0xfff0), (uint16_t)((h + 15) & 0xfff0));
        if (!s) { logf_("surface %d: NvMediaVideoSurfaceCreate failed", g_nPics); break; }
        g_pics[g_nPics].surface = s; g_pics[g_nPics].refs = 0; g_pics[g_nPics].index = g_nPics;
    }
    logf_("surfaces: %d of %d created (type %d, %ux%u)", g_nPics, want, type, (w + 15) & 0xfff0, (h + 15) & 0xfff0);
    if (g_nPics < 2) return 0;
    g_copyBuf = malloc((size_t)w * h * 2);
    return nBuf;
}

static int cb_alloc(void *ctx, void **out)
{
    (void)ctx;
    int i;
    *out = NULL;
    for (i = 0; i < g_nPics; i++)
        if (g_pics[i].refs == 0) { g_pics[i].refs = 1; *out = &g_pics[i]; return 1; }
    logf_("alloc: no free picture buffer");
    return 0;
}
static void cb_addref(void *ctx, void *p) { (void)ctx; if (p) ((Pic *)p)->refs++; }
static void cb_release(void *ctx, void *p) { (void)ctx; if (p && ((Pic *)p)->refs > 0) ((Pic *)p)->refs--; }
static void cb_nalu(void *ctx, const uint8_t *p, int n) { (void)ctx; (void)p; (void)n; }

/* The decoder's picture description, built field by field as libnvss_video.so
 * builds it at 0x50e0..0x52a8 from the parser's picture data. */
static int cb_decode(void *ctx, void *pd)
{
    (void)ctx;
    static uint8_t pic[0x2d8];
    static const struct { uint16_t to, from; uint8_t byteSrc; } bytes[] = {
        {0x10,0x0c,0},{0x11,0x10,0},{0x12,0x88,0},{0x13,0xb6,1},{0x14,0xb7,1},{0x15,0xa4,0},{0x16,0xa8,0},
        {0x17,0x80,0},{0x18,0xb5,1},{0x19,0xba,1},{0x1a,0xbb,1},{0x1b,0xac,0},{0x1c,0x9c,0},{0x1d,0xa0,0},
        {0x1e,0x70,0},{0x1f,0x74,0},{0x20,0x78,0},{0x21,0x7c,0},{0x22,0x84,0},{0x23,0xb8,1},{0x24,0xb9,1},
        {0x25,0xb4,1},{0x26,0xb0,0},{0x27,0xca,1},{0x28,0xcb,1},{0x34,0xc8,1},{0x35,0xc9,1},
    };
    unsigned i;
    g_stage = "DecodePicture";
    Pic *cur = (Pic *)(uintptr_t)rd32(pd, 0x08);
    if (!cur || !cur->surface) { logf_("decode: no current picture buffer"); return 0; }
    if (g_decoded >= g_maxPictures) return 1;

    memset(pic, 0, sizeof(pic));
    wr32(pic, 0x00, rd32(pd, 0xc0));
    wr32(pic, 0x04, rd32(pd, 0xc4));
    wr32(pic, 0x08, rd32(pd, 0x24));
    wr16(pic, 0x0c, rd16(pd, 0x2c));
    wr16(pic, 0x0e, rd16(pd, 0xbc));
    for (i = 0; i < sizeof(bytes) / sizeof(bytes[0]); i++)
        wr8(pic, bytes[i].to, bytes[i].byteSrc ? rd8(pd, bytes[i].from) : (uint8_t)rd32(pd, bytes[i].from));
    wr32(pic, 0x2c, rd32(pd, 0xd0));
    wr32(pic, 0x30, rd32(pd, 0xd4));
    memcpy(pic + 0x36, (uint8_t *)pd + 0x660, 0x60);
    memcpy(pic + 0x96, (uint8_t *)pd + 0x6c0, 0x80);
    for (i = 0; i < 16; i++) {
        unsigned s = 0xe0 + i * 0x1c, d = 0x118 + i * 0x1c;
        Pic *ref = (Pic *)(uintptr_t)rd32(pd, s);
        uint32_t flags = rd32(pd, s + 0x10);
        wr32(pic, d + 0x00, ref ? (uint32_t)(uintptr_t)ref->surface : 0);
        wr32(pic, d + 0x04, rd32(pd, s + 0x08));
        wr32(pic, d + 0x08, flags & 1);
        wr32(pic, d + 0x0c, (flags >> 1) & 1);
        wr32(pic, d + 0x10, rd32(pd, s + 0x14));
        wr32(pic, d + 0x14, rd32(pd, s + 0x18));
        wr16(pic, d + 0x18, (uint16_t)rd32(pd, s + 0x04));
    }
    uint32_t bs[2];
    bs[0] = rd32(pd, 0x38);     /* the bytes */
    bs[1] = rd32(pd, 0x34);     /* how many */
    if (g_decoded < 3) logf_("decode %u: %u bytes at %p into surface %d", g_decoded, (unsigned)bs[1], (void *)(uintptr_t)bs[0], cur->index);

    g_stage = "NvMediaVideoDecoderRender";
    double t = now_ms();
    int rc = NvMediaVideoDecoderRender(g_decoder, cur->surface, pic, 1, bs);
    double d = now_ms() - t;
    g_renderMs += d; if (d > g_renderMax) g_renderMax = d;
    if (rc != 0) { if (g_renderFail++ < 5) logf_("decode %u: NvMediaVideoDecoderRender = %d (0x%x)", g_decoded, rc, (unsigned)rc); return 0; }
    g_decoded++;
    return 1;
}

static void inspect(Pic *p)
{
    static uint32_t map[128];
    g_stage = "NvMediaVideoSurfaceLock";
    memset(map, 0, sizeof(map));
    double t = now_ms();
    int rc = NvMediaVideoSurfaceLock(p->surface, map);
    double lockMs = now_ms() - t;
    if (rc != 0) { if (g_lockFail++ < 5) logf_("show %u: NvMediaVideoSurfaceLock = %d (0x%x)", g_shown, rc, (unsigned)rc); return; }
    g_lockMs += lockMs; g_locks++;

    g_stage = "reading the lock map";
    if (g_shown < 2) {
        char line[400]; int n = 0, i;
        for (i = 0; i < 24; i++) n += snprintf(line + n, sizeof(line) - n, "%08x ", (unsigned)map[i]);
        logf_("show %u: lock took %.2f ms; map words: %s", g_shown, lockMs, line);
    }
    if (g_yWord < 0) {
        /* The luma plane: the first word that is a readable address for a whole plane. */
        int i;
        for (i = 0; i < 24 && g_yWord < 0; i++)
            if (readable((void *)(uintptr_t)map[i], (size_t)g_w * g_h)) g_yWord = i;
        if (g_yWord >= 0 && g_yWord + 1 < 24 && map[g_yWord + 1] >= g_w && map[g_yWord + 1] <= g_w + 256)
            g_pitchWord = g_yWord + 1;      /* the pitch follows its plane */
        logf_("show %u: luma plane taken from map word %d, pitch from word %d (%u)", g_shown, g_yWord,
              g_pitchWord, g_pitchWord >= 0 ? (unsigned)map[g_pitchWord] : 0);
        for (i = 0; i < 24; i++)
            if (readable((void *)(uintptr_t)map[i], 4096)) {
                const uint8_t *q = (const uint8_t *)(uintptr_t)map[i]; unsigned k, sum = 0;
                for (k = 0; k < 4096; k++) sum += q[k];
                logf_("  word %d -> %p: mean of first 4096 bytes %u", i, (void *)q, sum / 4096);
            }
    }
    if (g_yWord >= 0 && g_copyBuf) {
        const uint8_t *y = (const uint8_t *)(uintptr_t)map[g_yWord];
        unsigned pitch = g_pitchWord >= 0 ? map[g_pitchWord] : g_w;
        g_stage = "copying the luma plane";
        if (readable(y, (size_t)pitch * (g_h - 1) + g_w)) {
            unsigned row; unsigned long sum = 0;
            t = now_ms();
            for (row = 0; row < g_h; row++) memcpy(g_copyBuf + (size_t)row * g_w, y + (size_t)row * pitch, g_w);
            g_copyMs += now_ms() - t; g_copies++;
            if (g_shown < 4 || g_shown % 60 == 0) {
                unsigned k; size_t step = ((size_t)g_w * g_h) / 4096;
                for (k = 0; k < 4096; k++) sum += g_copyBuf[k * step];
                logf_("show %u: luma mean %lu, centre pixel %u, corner %u", g_shown, sum / 4096,
                      g_copyBuf[(size_t)(g_h / 2) * g_w + g_w / 2], g_copyBuf[0]);
            }
        }
    }
    g_stage = "NvMediaVideoSurfaceUnlock";
    NvMediaVideoSurfaceUnlock(p->surface);
}

static int cb_display(void *ctx, void *p, long long pts)
{
    (void)ctx; (void)pts;
    g_stage = "DisplayPicture";
    if (p && ((Pic *)p)->surface) { inspect((Pic *)p); g_shown++; }
    return 1;
}

#define LOAD(lib, name) do { *(void **)(&name) = dlsym(lib, #name); \
    if (!name) { logf_("missing: %s", #name); missing++; } } while (0)

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "nvprobe <file.h264> <log> [max pictures]\n"); return 2; }
    g_log = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (argc > 3) g_maxPictures = (unsigned)atoi(argv[3]);
    g_devnull = open("/dev/null", O_WRONLY);
    signal(SIGSEGV, on_signal); signal(SIGBUS, on_signal); signal(SIGILL, on_signal);
    signal(SIGALRM, on_signal); signal(SIGFPE, on_signal);
    alarm(60);
    logf_("nvprobe 2: %s", argv[1]);

    g_stage = "dlopen";
    void *nm = dlopen("libnvmedia.so", RTLD_NOW | RTLD_GLOBAL);
    if (!nm) { logf_("dlopen libnvmedia.so: %s", dlerror()); return 1; }
    void *np = dlopen("libnvparser.so", RTLD_NOW | RTLD_GLOBAL);
    if (!np) { logf_("dlopen libnvparser.so: %s", dlerror()); return 1; }
    int missing = 0;
    LOAD(nm, NvMediaDeviceCreate); LOAD(nm, NvMediaDeviceDestroy);
    LOAD(nm, NvMediaVideoDecoderCreate); LOAD(nm, NvMediaVideoDecoderDestroy); LOAD(nm, NvMediaVideoDecoderRender);
    LOAD(nm, NvMediaVideoSurfaceCreate); LOAD(nm, NvMediaVideoSurfaceDestroy);
    LOAD(nm, NvMediaVideoSurfaceLock); LOAD(nm, NvMediaVideoSurfaceUnlock);
    LOAD(np, video_parser_create); LOAD(np, video_parser_destroy);
    LOAD(np, video_parser_parse); LOAD(np, video_parser_set_attribute);
    if (missing) return 1;
    logf_("libraries: loaded, all 13 functions found");

    FILE *f = fopen(argv[1], "rb");
    if (!f) { logf_("cannot open %s: %s", argv[1], strerror(errno)); return 1; }

    g_stage = "NvMediaDeviceCreate";
    g_device = NvMediaDeviceCreate();
    logf_("device: NvMediaDeviceCreate = %p", g_device);
    if (!g_device) return 1;

    /* Parser set-up as at 0x5944..0x5a28: seven callbacks, then
     * {callbacks, context, clock rate 1000000, error threshold 50, H.264 = 4}. */
    static void *callbacks[12];
    static uint32_t params[16];
    callbacks[0] = (void *)cb_begin;   callbacks[1] = (void *)cb_decode; callbacks[2] = (void *)cb_display;
    callbacks[3] = (void *)cb_nalu;    callbacks[4] = (void *)cb_alloc;  callbacks[5] = (void *)cb_release;
    callbacks[6] = (void *)cb_addref;
    params[0] = (uint32_t)(uintptr_t)callbacks; params[1] = (uint32_t)(uintptr_t)params;
    params[2] = 1000000; params[3] = 50; params[4] = 4;
    g_stage = "video_parser_create";
    void *parser = video_parser_create(params);
    logf_("parser: video_parser_create = %p", parser);
    if (!parser) return 1;
    { uint8_t one = 1; g_stage = "video_parser_set_attribute"; int rc = video_parser_set_attribute(parser, 4, 1, &one);
      logf_("parser: set_attribute(4, 1) = %d", rc); }

    static uint8_t chunk[32768];
    static uint32_t packet[16];
    size_t n, total = 0; int parseFail = 0;
    double t0 = now_ms(); clock_t c0 = clock();
    while ((n = fread(chunk, 1, sizeof(chunk), f)) > 0 && g_decoded < g_maxPictures) {
        memset(packet, 0, sizeof(packet));
        packet[0] = (uint32_t)(uintptr_t)chunk; packet[1] = (uint32_t)n;
        g_stage = "video_parser_parse";
        int rc = video_parser_parse(parser, packet);
        if (!rc && parseFail++ < 3) logf_("parse: returned 0 after %lu bytes", (unsigned long)total);
        total += n;
    }
    memset(packet, 0, sizeof(packet)); packet[2] = 1;    /* end of stream: hands out the last pictures */
    g_stage = "video_parser_parse (end of stream)";
    video_parser_parse(parser, packet);
    double wall = now_ms() - t0; double cpu = (clock() - c0) * 1000.0 / CLOCKS_PER_SEC;
    fclose(f);

    logf_("RESULT: %lu bytes fed, %u pictures decoded, %u handed out, %u decode failures, %u lock failures",
          (unsigned long)total, g_decoded, g_shown, g_renderFail, g_lockFail);
    if (g_decoded)
        logf_("RESULT: %.0f ms in all = %.1f pictures a second; decode call %.2f ms average, %.2f ms longest",
              wall, g_decoded * 1000.0 / wall, g_renderMs / g_decoded, g_renderMax);
    if (g_locks)
        logf_("RESULT: lock %.2f ms average over %u; luma copy %.2f ms average over %u", g_lockMs / g_locks, g_locks,
              g_copies ? g_copyMs / g_copies : 0.0, g_copies);
    logf_("RESULT: processor time used by this program %.0f ms of %.0f ms (%.0f %%)", cpu, wall, wall > 0 ? cpu * 100.0 / wall : 0.0);

    g_stage = "closing";
    video_parser_destroy(parser);
    if (g_decoder) NvMediaVideoDecoderDestroy(g_decoder);
    { int i; for (i = 0; i < g_nPics; i++) NvMediaVideoSurfaceDestroy(g_pics[i].surface); }
    NvMediaDeviceDestroy(g_device);
    logf_("closed cleanly");
    return 0;
}
