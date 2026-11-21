// opengl-render-qnx-stream-player — pipelined multithreaded stream renderer
//
// Dual-Target Unified Architecture:
// - QNX ARM: OpenKODE (libdisplayinit.so) + GLES2 hardware texture mapping (Tegra 3 proven)
// - x86/Linux: GLFW + GLES2 hardware texture mapping
//
// Features:
// - 6-slot lock-free frame pool (zero runtime heap allocations inside 30 FPS loop)
// - Monotonic target clock pacer locked to 30.00 FPS
// - Direct fast YUV420p -> RGBA CPU conversion with macroblock stride compensation
// - 4-line centered HUD overlay rendered directly into RGBA buffer (immune to GL state bugs)
// - Seamless dual-mode: local file replay (--loop) and direct socket streaming (tcp://...)
// - Factory-safe DMDT display context activation (Context 3) and clean restoration (Context 33)

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <sched.h>
#include <time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <malloc.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <stddef.h>

#ifdef __QNX__
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <sys/syspage.h>
#else
#include <GLES2/gl2.h>
#include <GLFW/glfw3.h>
#endif

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/cpu.h>
}

// ---------------- Configuration & Performance Knobs ----------------
static const int kBufferPoolSize    = 16;     // 16-slot frame pool for jitter smoothing & zero contention
static int   g_ffmpegThreadCount    = 2;      // Default: 2 worker threads for multi-core Tegra 3
/*
 * Zero frame delay by default. Frame threading holds each decoded frame until
 * the next packet arrives, and the render ACK the phone is waiting for only
 * comes after that frame is shown. When the phone is short of window credit it
 * sends the next packet only after that ACK, so every frame waits for a
 * phone-side timeout of about 300 ms: 3.3 fps with 313 ms ACK latency, seen on
 * the car 2026-09-16 (run 3). AV_CODEC_FLAG_LOW_DELAY makes FFmpeg skip frame
 * threading altogether; slice threading is declared too so the startup log
 * does not claim otherwise. Decode at 800x480 measured about 1 ms a frame, so
 * frame-parallel decode bought nothing. Not configurable: this is a fix, and
 * the old GAL_PLAYER_THREAD_TYPE / GAL_PLAYER_LOW_DELAY knobs (conf, env and
 * --thread-type / --low-delay flags) could only put the stall back.
 */
static const int  g_ffmpegThreadType = FF_THREAD_SLICE;
static const bool g_ffmpegLowDelay   = true;
static bool  g_ffmpegFastDecode     = true;
static int   g_ffmpegSkipFrame      = AVDISCARD_DEFAULT;
static int   g_ffmpegSkipLoopFilter = AVDISCARD_NONREF; // Default: noref eliminates macroblock prediction blur during movement
static int   g_idleMaxBytes         = 0;      // Stationary frame threshold (default: 0 = disabled for pure 30 FPS)
static int   g_idleHeartbeatHz      = 0;      // Stationary heartbeat keepalive rate in Hz (default: 0 = disabled)
static bool  g_loopFile             = false;
static bool  g_verbose              = true;
#ifndef __QNX__
static char  g_dumpVideoPath[512]   = {0};
static int   g_dumpMaxFrames        = 0;
static int   g_dumpFrameCount       = 0;
static FILE* g_dumpVideoPipe        = NULL;
#endif

// ---------------- Logging ----------------
#define LOG(fmt, ...) do {     printf("[stream-player] " fmt "\n", ##__VA_ARGS__);     fflush(stdout); } while(0)

#define LOG_STATS(fmt, ...) do {     printf("[stream-player STATS] " fmt "\n", ##__VA_ARGS__);     fflush(stdout); } while(0)

#define LOGE(fmt, ...) do {     fprintf(stderr, "[stream-player ERROR] " fmt "\n", ##__VA_ARGS__);     fflush(stderr); } while(0)

static inline uint8_t clamp8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

static uint64_t now_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)(ts.tv_nsec / 1000ULL);
}

static double us_to_ms(uint64_t us) {
    return (double)us / 1000.0;
}

static double get_process_memory_mb() {
#ifdef __QNX__
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/as", getpid());
    int fd = open(path, O_RDONLY);
    if (fd >= 0) {
        struct stat st;
        if (fstat(fd, &st) == 0) {
            close(fd);
            return (double)st.st_size / (1024.0 * 1024.0);
        }
        close(fd);
    }
    return 0.0;
#else
    FILE* f = fopen("/proc/self/statm", "r");
    if (f) {
        long total_pages = 0, rss_pages = 0;
        if (fscanf(f, "%ld %ld", &total_pages, &rss_pages) == 2) {
            fclose(f);
            long page_size_kb = sysconf(_SC_PAGESIZE) / 1024;
            return (double)(rss_pages * page_size_kb) / 1024.0;
        }
        fclose(f);
    }
    return 0.0;
#endif
}

// ---------------- Frame Buffer Structures ----------------
struct RGBABuffer {
    uint8_t* pixels;
    int width;
    int height;
    size_t capacity;
    int packetBytes;
    bool isKeyframe;
    bool colorFull;   /* the stream says full range (0-255), not 16-235 */
    bool colorBt709;  /* the stream says BT.709, or is HD and says nothing */

    RGBABuffer() : pixels(NULL), width(0), height(0), capacity(0), packetBytes(0), isKeyframe(false),
                   colorFull(false), colorBt709(false) {}

    void ensureCapacity(int w, int h) {
        size_t total = (size_t)w * h + 2 * ((size_t)(w/2) * (h/2));
        if (capacity < total) {
            free(pixels);
            pixels = (uint8_t*)malloc(total);
            capacity = total;
        }
        width = w;
        height = h;
    }

    void release() { free(pixels); pixels = NULL; capacity = 0; }
};

// 6-Slot Ring Buffer Pool
struct FramePool {
    RGBABuffer slots[kBufferPoolSize];
    int writeSlot;
    int readySlot;
    int readSlot;

    FramePool() : writeSlot(0), readySlot(-1), readSlot(-1) {}

    RGBABuffer* getWriteBuffer(int w, int h) {
        slots[writeSlot].ensureCapacity(w, h);
        return &slots[writeSlot];
    }

    void publishWrite() {
        readySlot = writeSlot;
        writeSlot = (writeSlot + 1) % kBufferPoolSize;
        if (writeSlot == readSlot) {
            writeSlot = (writeSlot + 1) % kBufferPoolSize;
        }
    }

    RGBABuffer* getDisplayBuffer() {
        if (readySlot >= 0) {
            readSlot = readySlot;
            readySlot = -1;
        }
        if (readSlot >= 0) return &slots[readSlot];
        return NULL;
    }
};

static FramePool g_framePool;
static pthread_mutex_t g_frameMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_frameCond  = PTHREAD_COND_INITIALIZER;

static volatile bool g_running = true;
static volatile int g_streamSock = -1;
static volatile bool g_newFrameReady = false;
static uint64_t g_decodedFrameCount = 0;
static uint64_t g_lastDecodeDurationUs = 0;
static char g_videoSource[512] = "tcp://127.0.0.1:12346";

/*
 * Buffered reader for the CarPlay stream (--no-ack). harman-f's hook queues
 * only 16 pictures for this player, about half a second, and drops the
 * player when that fills ("gen2 video AU rc=2 -> consumer reset"), which
 * puts the car's own map back. Reading and decoding on one thread meant one
 * slow stretch of large pictures was enough (#10, #19, #43: 4 of 5 switches
 * back in one capture). A second thread now keeps the socket drained into
 * this buffer, and while the decoder is behind it skips the loop filter to
 * catch up. Android Auto keeps its ACK pacing and does not use this.
 */
static bool g_bufferedReader = false;
static const size_t kReaderBufBytes   = 8u * 1024u * 1024u;
static const size_t kReaderBehindOn   = 192u * 1024u;  // "behind" above this backlog (loop filter kept on reference pictures)
static const size_t kReaderBehindOff  = 64u * 1024u;   // and restore it below this
static uint8_t* g_rb = NULL;
static size_t g_rbHead = 0, g_rbFill = 0, g_rbHigh = 0;
static bool g_rbClosed = false;
static uint64_t g_rbBehindEpisodes = 0;

/*
 * Jumping to the present (#19, #10). The iPhone sends a keyframe only when
 * asked (2 in 5540 pictures in one capture), so catching up by decoding
 * faster took 2 to 8 s each time. Above kReaderJumpOn the player asks the
 * hook for one through its manual resync markers; the reader watches the
 * incoming bytes for it, and the decoder then skips everything queued before
 * it, as luka-dev's MHI2Q renderer does. If none comes, nothing is skipped.
 */
static const size_t kReaderJumpOn = 512u * 1024u;
static const char* kResyncEnableMarker = "/tmp/mibr-alt111-resync.enabled";
static const char* kResyncArmMarker = "/tmp/mibr-alt111-resync-arm";
static bool g_rbJumpWanted = false, g_rbJumpFound = false;
static uint64_t g_rbJumpAt = 0;                // stream offset of the keyframe's start code
static uint64_t g_rbWritten = 0, g_rbRead = 0; // stream offsets written and taken
static unsigned g_rbScanZeros = 0;
static bool g_rbScanHeader = false;
static uint64_t g_rbJumps = 0;

/* Brightness of a recent decoded picture, 0-255, for the health line (#4). */
static volatile unsigned g_lastLuma = 0;
static pthread_mutex_t g_rbMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_rbCond  = PTHREAD_COND_INITIALIZER;
static bool g_isSocket = false;

int windowWidth  = 800;
int windowHeight = 480;
static int g_streamFrameWidth = 800;
static int g_streamFrameHeight = 480;

static GLfloat backgroundColor[4] = { 0.0f, 0.0f, 0.0f, 1.0f };

/*
 * The window is the cluster map window's size (GAL_PLAYER_WINDOW), which on
 * some clusters is not 800x480 while Android Auto's frame always is. There
 * the hook asks the phone to leave margins (GAL_SECONDARY_MARGINS) so that
 * the rest of the frame has the window's shape; they are cropped off here
 * and the rest fills the window. A CarPlay stream is asked for at the
 * window's size and fills it as it is. Anything else that still differs in
 * shape is drawn centred at its own shape, with black bars. GAL_CROP_TOP or
 * GAL_CROP_BOTTOM switches Android Auto to a full-frame crop and stretches
 * the remaining rows over the window.
 */
/*
 * Margins cost picture: on a 1010x376 window only 298 of the 480 lines carry
 * map. With CLUSTERMAP_FULL_FRAME the installer sets no margins and declares
 * non-square pixels instead (GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4, 16117 for
 * 1010x376), so the phone draws on the whole frame, squeezed, and the frame
 * is stretched back here. 10000 is square pixels: no change.
 * (From AMDFX60's fork, reported car-tested on a Skoda Superb.)
 */
static int g_marginW = 0, g_marginH = 0;
static int g_cropTop = 0, g_cropBottom = 0;
static int g_pixelAspectE4 = 10000;
static int g_priority = 0;      /* GAL_PLAYER_PRIORITY, 0 = as spawned */
static int g_priorityCap = 0;   /* GAL_PLAYER_PRIORITY_CAP, 0 = off: lower to this if above */
static bool g_primaryWatch = false; /* GAL_DEBUG_PRIMARY=1 or GAL_PRIMARY_RESTART_PAUSE_MS set (#125) */
static bool g_selectAtStart = true; /* GAL_PLAYER_SELECT_AT_START=0: no 'dmdt sc' at the first picture */
/* GAL_PLAYER_NEON (default 1), and the marker a crash leaves: while it is
 * there (until the next reboot) the player decodes without NEON. */
static bool g_neonAllowed = true;
static const char kNoNeonMarker[] = "/tmp/clustermap-player-noneon";
static GLfloat fittedVertices[12];
static GLfloat croppedTexCoords[8];
static bool g_lumaExact = false;
static void fit_frame(int frameW, int frameH) {
    float sx = 1.0f, sy = 1.0f, cu = 0.0f, cv = 0.0f;
    float cu1 = 1.0f, cv1 = 1.0f, par = 1.0f;
    int contentW = frameW, contentH = frameH;
    int marginTop = 0, marginLeft = 0;
    bool hdFrame = (frameW == 1280 && frameH == 720) ||
                   (frameW == 1920 && frameH == 1080);
    bool cropConfigured = frameW == 800 && frameH == 480 &&
                          (g_cropTop > 0 || g_cropBottom > 0) &&
                          g_cropTop + g_cropBottom < frameH;
    if (frameW == 800 && frameH == 480) {
        if (cropConfigured) {
            contentH = frameH - g_cropTop - g_cropBottom;
            cu = 0.0f;
            cv = (float)g_cropTop / (float)frameH;
            const GLfloat t[8] = {
                0.0f, cv,
                1.0f, cv,
                1.0f, 1.0f - (float)g_cropBottom / (float)frameH,
                0.0f, 1.0f - (float)g_cropBottom / (float)frameH,
            };
            memcpy(croppedTexCoords, t, sizeof t);
        } else if (g_marginW > 0 || g_marginH > 0) {
            marginLeft = g_marginW / 2;
            marginTop = g_marginH / 2;
            contentW = frameW - g_marginW;
            contentH = frameH - g_marginH;
            cu = (float)marginLeft / (float)frameW;
            cv = (float)marginTop / (float)frameH;
            cu1 = 1.0f - cu;
            cv1 = 1.0f - cv;
        }
        par = (float)g_pixelAspectE4 / 10000.0f;
    } else if (hdFrame && g_marginW >= 0 && g_marginH >= 0 &&
               g_marginW < frameW && g_marginH < frameH) {
        int marginRight = g_marginW - g_marginW / 2;
        int marginBottom = g_marginH - g_marginH / 2;
        contentW = frameW - g_marginW;
        contentH = frameH - g_marginH;
        cu = (float)(g_marginW / 2) / (float)frameW;
        cv = (float)(g_marginH / 2) / (float)frameH;
        cu1 = 1.0f - (float)marginRight / (float)frameW;
        cv1 = 1.0f - (float)marginBottom / (float)frameH;
    }
    if (!cropConfigured && contentW > 0 && contentH > 0) {
        float contentAspect = (float)contentW * par / (float)contentH;
        float windowAspect = (float)windowWidth / (float)windowHeight;
        if (contentAspect > windowAspect * 1.01f) sy = windowAspect / contentAspect;
        else if (contentAspect < windowAspect * 0.99f) sx = contentAspect / windowAspect;
    }
    const GLfloat v[12] = { -sx, sy, 0.0f,  sx, sy, 0.0f,  sx, -sy, 0.0f,  -sx, -sy, 0.0f };
    if (!cropConfigured) {
        const GLfloat t[8] = { cu, cv,  cu1, cv,  cu1, cv1,  cu, cv1 };
        memcpy(croppedTexCoords, t, sizeof t);
    }
    memcpy(fittedVertices, v, sizeof v);
    g_lumaExact = hdFrame && !cropConfigured && sx == 1.0f && sy == 1.0f &&
                  par == 1.0f && contentW == windowWidth &&
                  contentH == windowHeight;
    if (hdFrame) {
        LOG("render: %dx%d frame, %dx%d after margins/crop, pixel aspect %.4f, crop=%s, in a %dx%d window, drawn %dx%d, %s",
            frameW, frameH, contentW, contentH, par, cropConfigured ? "stretch" : "off", windowWidth, windowHeight,
            (int)(sx * windowWidth + 0.5f), (int)(sy * windowHeight + 0.5f),
            g_lumaExact ? "1:1 (exact pixels)" : "scaled");
    } else {
        LOG("render: %dx%d frame, %dx%d after margins/crop, pixel aspect %.4f, crop=%s, in a %dx%d window, drawn %dx%d",
            frameW, frameH, contentW, contentH, par, cropConfigured ? "stretch" : "off", windowWidth, windowHeight,
            (int)(sx * windowWidth + 0.5f), (int)(sy * windowHeight + 0.5f));
    }
}

#ifdef __QNX__
static void* g_displayInitHandle = NULL;
static EGLDisplay eglDisplay = EGL_NO_DISPLAY;
static EGLSurface eglSurface = EGL_NO_SURFACE;
static EGLContext eglContext = EGL_NO_CONTEXT;
#else
static GLFWwindow* g_glfwWindow = NULL;
#endif

#ifdef __QNX__
typedef void (*PFNGLDRAWTEXTURENVPROC)(GLuint texture, GLuint sampler,
                                       GLfloat x0, GLfloat y0,
                                       GLfloat x1, GLfloat y1,
                                       GLfloat z,
                                       GLfloat s0, GLfloat t0,
                                       GLfloat s1, GLfloat t1);
static PFNGLDRAWTEXTURENVPROC g_pfnDrawTextureNV = NULL;
#endif
static bool g_useShader = false;

static GLuint g_programObject = 0;
static GLint  g_posAttr = -1;
static GLint  g_texAttr = -1;
static GLint  g_texLocY = -1;
static GLint  g_texLocU = -1;
static GLint  g_texLocV = -1;
static GLint  g_rangeLoc = -1;
static GLint  g_matrixLoc = -1;
/*
 * Colour conversion (found by AMDFX60's Skoda fork, 2026-11). The player used
 * full-range BT.601 for every stream, but a phone's H.264 is normally limited
 * range (Y 16-235, Cb/Cr 16-240): grey blacks, dim whites, paler colours.
 * GAL_PLAYER_COLOR=auto (the default) follows what the stream says, assuming
 * limited range when it says nothing (the H.264 default) and BT.709 for an HD
 * frame that names no matrix; old is the previous conversion, to compare.
 */
static bool g_colorAuto = true;
static GLuint g_texY = 0;
static GLuint g_texU = 0;
static GLuint g_texV = 0;

// Standard GLES2 RGBA Shaders (Proven 100% compatible with Tegra 3)
static const char* vertexShaderSource =
    "attribute vec2 position;    \n"
    "attribute vec2 texCoord;     \n"
    "varying vec2 v_texCoord;     \n"
    "void main()                  \n"
    "{                            \n"
    "   gl_Position = vec4(position, 0.0, 1.0); \n"
    "   v_texCoord = texCoord;   \n"
    "}                            \n";

static const char* fragmentShaderSource =
    "precision mediump float;\n"
    "varying vec2 v_texCoord;\n"
    "uniform sampler2D texY;\n"
    "uniform sampler2D texU;\n"
    "uniform sampler2D texV;\n"
    "uniform vec3 range;\n"   /* Y offset, Y scale, Cb/Cr scale */
    "uniform vec4 matrix;\n"  /* Cr->R, Cb->G, Cr->G, Cb->B */
    "void main()\n"
    "{\n"
    "    float y = (texture2D(texY, v_texCoord).r - range.x) * range.y;\n"
    "    float u = (texture2D(texU, v_texCoord).r - 0.5) * range.z;\n"
    "    float v = (texture2D(texV, v_texCoord).r - 0.5) * range.z;\n"
    "    float r = y + matrix.x * v;\n"
    "    float g = y - matrix.y * u - matrix.z * v;\n"
    "    float b = y + matrix.w * u;\n"
    "    gl_FragColor = vec4(r, g, b, 1.0);\n"
    "}\n";

// ---------------- QNX DMDT Context Switching ----------------
/* The cockpit-context check further down; here so both builds have them. */
static bool g_reassert = false;               /* GAL_PLAYER_REASSERT=1 */
static volatile int g_ctxShown = -1;          /* -1 not read yet, -2 context not listed */
static volatile bool g_switchDone = false;
/*
 * The cluster shows this player when context 70 points at displayable 3 (and
 * display 4 shows context 70); the stock Kombi map is displayable 33. Both
 * are set with dmdt, a separate process that took about 0.3 s a run on the
 * car. Android Auto allows 500 ms of video setup latency, on-screen
 * transition included, and 50 ms of output latency (HUIG 1.3 p.36).
 *
 * So the switch starts the moment the decoder has the phone's first keyframe
 * -- the hook grants the stream only once the Kombi map is ready, so nothing
 * is probed or waited for here -- and runs on its own threads, both commands
 * at once, while the render loop keeps drawing and ACKing. It used to wait
 * for 30 decoded frames (1 s), probe `dmdt gs` for the Kombi map, then run
 * the two commands one after the other on the render thread: about 2 s before
 * the cluster changed, with render ACKs held back 0.3-1.25 s at the switch
 * (car, 2026-09-16). Timestamps are CLOCK_MONOTONIC, the hook log's clock.
 */
#define T_ARGS(us) (unsigned long long)((us) / 1000000ULL), (unsigned long long)((us) / 1000ULL % 1000ULL)
static pid_t g_parentPid = 0;
/*
 * The numbers above are VW's, SEAT's and Skoda's. An Audi A4 B9 (K3346, #14)
 * shows its map in context 72 or 74 instead, so they come from
 * GAL_VC_CONTEXT, GAL_VC_DISPLAY, GAL_VC_DISPLAYABLE_ID and
 * GAL_VC_RESTORE_DISPLAYABLE_ID, the hook's own keys. The dmdt arguments are
 * built once at start-up, so the crash handler only reads them.
 */
static unsigned g_vcContext = 70u;
static unsigned g_vcDisplay = 4u;
static unsigned g_vcDisplayable = 3u;
static unsigned g_vcRestore = 33u;
static char g_dmdtShow[32] = "dc 70 3";
static char g_dmdtRestore[32] = "dc 70 33";
static char g_dmdtSelect[32] = "sc 4 70";
static char g_dmdtCrashCmd[320] = "";
static void build_dmdt_args() {
    snprintf(g_dmdtShow, sizeof(g_dmdtShow), "dc %u %u", g_vcContext, g_vcDisplayable);
    snprintf(g_dmdtRestore, sizeof(g_dmdtRestore), "dc %u %u", g_vcContext, g_vcRestore);
    snprintf(g_dmdtSelect, sizeof(g_dmdtSelect), "sc %u %u", g_vcDisplay, g_vcContext);
    snprintf(g_dmdtCrashCmd, sizeof(g_dmdtCrashCmd),
             "LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production /eso/bin/apps/dmdt %s 2>/dev/null; "
             "LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production /eso/bin/apps/dmdt %s 2>/dev/null",
             g_dmdtRestore, g_dmdtSelect);
}
#ifdef __QNX__
struct DmdtRun { const char* args; int status; };

static void* dmdt_run_thread(void* arg) {
    DmdtRun* run = (DmdtRun*)arg;
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production /eso/bin/apps/dmdt %s 2>/dev/null",
             run->args);
    run->status = system(cmd);
    return NULL;
}

/*
 * Run the two dmdt commands sequentially: dc rewrites the context table,
 * and sc commits the displayable to the MOST encoder. sc must not run before dc.
 * Because display_switch_thread is already off the render thread, running
 * them sequentially does not block rendering or hold back frame ACKs.
 */
static void dmdt_pair(const char* a, const char* b, const char* what) {
    DmdtRun runs[2] = { { a, -1 }, { b, -1 } };
    uint64_t start = now_us();
    dmdt_run_thread(&runs[0]);
    dmdt_run_thread(&runs[1]);
    uint64_t end = now_us();
    LOG("dmdt: %s t=%llu.%03llu took=%llums ('dmdt %s'=%d, 'dmdt %s'=%d)", what, T_ARGS(end),
        (unsigned long long)((end - start) / 1000ULL), a, runs[0].status, b, runs[1].status);
}

static pthread_mutex_t g_switchLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t g_switchThread;
static bool g_switchStarted = false;   /* g_switchLock */
static bool g_switchClosed = false;    /* g_switchLock: shutting down */

static void* display_switch_thread(void* arg) {
    (void)arg;
    if (!g_selectAtStart) {
        /* #145: 'sc' also brings the cockpit's map view up between the dials,
         * whatever view the driver chose. Only put the player in the context. */
        DmdtRun run = { g_dmdtShow, -1 };
        uint64_t start = now_us();
        dmdt_run_thread(&run);
        LOG("dmdt: player put in the cockpit context, view left to the driver (GAL_PLAYER_SELECT_AT_START=0) t=%llu.%03llu took=%llums ('dmdt %s'=%d)",
            T_ARGS(now_us()), (unsigned long long)((now_us() - start) / 1000ULL), g_dmdtShow, run.status);
    } else
    dmdt_pair(g_dmdtShow, g_dmdtSelect, "cluster switched to the player");
    LOG("context: checked once a minute; switching back is %s (GAL_PLAYER_REASSERT)", g_reassert ? "on" : "off");
    g_switchDone = true;
    return NULL;
}

#ifdef __QNX__
#include <signal.h>
#include <sys/select.h>
#include <sys/wait.h>
/*
 * The settings hold the map window's size as the installer read it, and the
 * display manager only lists the window once the cockpit has shown it, so that
 * can be a guess (#52, #56). When the player starts the cockpit is up: use the
 * real size, because a wrong one arrives on the cockpit as stripes. This run's
 * picture was laid out for the old size and is drawn centred at its own shape;
 * window_fix.sh corrects the settings for the next start.
 */
/*
 * Run one dmdt query (gd, gs) and return its text. dmdt buffers its output
 * when it is not a terminal, hence the flush shim. Two seconds at most: a
 * stuck display tool must not cost the map.
 */
static size_t dmdt_capture(const char* query, char* out, size_t outSize) {
    char cmd[320];
    int fds[2];
    size_t used = 0u;
    pid_t pid;
    out[0] = 0;
    if (pipe(fds) != 0) return 0u;
    snprintf(cmd, sizeof(cmd),
             "cd /eso && LD_PRELOAD=/eso/lib/gal_dualscreen/libdmdt_flush.so "
             "LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production "
             "exec ./bin/apps/dmdt %s 2>/dev/null", query);
    pid = fork();
    if (pid < 0) {
        close(fds[0]);
        close(fds[1]);
        return 0u;
    }
    if (pid == 0) {
        dup2(fds[1], 1);
        close(fds[0]);
        close(fds[1]);
        execl("/bin/sh", "sh", "-c", cmd, (char*)NULL);
        _exit(127);
    }
    close(fds[1]);
    for (int waited = 0; waited < 20 && used + 1u < outSize;) {
        struct timeval tv = { 0, 100000 };
        fd_set rd;
        FD_ZERO(&rd);
        FD_SET(fds[0], &rd);
        int ready = select(fds[0] + 1, &rd, NULL, NULL, &tv);
        if (ready == 0) { ++waited; continue; }
        if (ready < 0) break;
        ssize_t n = read(fds[0], out + used, outSize - 1u - used);
        if (n <= 0) break;
        used += (size_t)n;
    }
    close(fds[0]);
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
    out[used] = 0;
    return used;
}

static bool g_windowFromArgs = false;
static void check_map_window() {
    char cmd[256], out[4096], type[32];
    int w = 0, h = 0, found = 0;
    if (g_windowFromArgs) return;
    if (dmdt_capture("gd", out, sizeof(out)) == 0u) return;
    for (char* line = strtok(out, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        unsigned id = 0u;
        int lw = 0, lh = 0;
        if (sscanf(line, " %u %31s %d x %d", &id, type, &lw, &lh) == 4 && id == g_vcRestore) {
            w = lw; h = lh; found = 1;
        }
    }
    if (!found || w < 320 || w > 1920 || h < 160 || h > 1080) {
        LOG("display: window %u not listed, keeping %dx%d from the settings",
            g_vcRestore, windowWidth, windowHeight);
        return;
    }
    if (w == windowWidth && h == windowHeight) return;
    LOG("display: the cockpit's map window is %dx%d, the settings say %dx%d; using %dx%d and correcting the settings for the next start",
        w, h, windowWidth, windowHeight, w, h);
    windowWidth = w;
    windowHeight = h;
    snprintf(cmd, sizeof(cmd), "sh /eso/lib/gal_dualscreen/window_fix.sh %d %d >/dev/null 2>&1 &", w, h);
    if (system(cmd) != 0) LOG("display: could not start window_fix.sh");
}

/*
 * Is the cockpit still on this player? The switch above is made once. On some
 * cars the context is later found back on the car's own map window while the
 * player is still drawing (#105 Tiguan K3342, #24 P4512_2): the owner sees
 * the phone's map for a moment, then the car's. What sets it back is not
 * known. So, five seconds after the switch and then once a minute, read
 * `dmdt gs` on a thread of its own and note which window the context shows;
 * the health line prints it. GAL_PLAYER_REASSERT=1 (off by default) also
 * switches the context to the player again when it is found elsewhere.
 */
static volatile bool g_ctxBusy = false;
static volatile uint64_t g_ctxNextUs = 0;
static pthread_t g_ctxThread;
static bool g_ctxThreadStarted = false;       /* main thread only */
static unsigned g_ctxReasserts = 0;           /* context thread only */

static int parse_context_window(char* out, unsigned context) {
    bool inContext = false;
    for (char* line = strtok(out, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        unsigned id = 0u;
        if (sscanf(line, " context id: %u", &id) == 1) { inContext = (id == context); continue; }
        if (inContext && sscanf(line, " %u (", &id) == 1) return (int)id;
    }
    return -2;
}

static void* context_check_thread(void* arg) {
    char out[4096];
    (void)arg;
    if (dmdt_capture("gs", out, sizeof(out)) != 0u) {
        int shown = parse_context_window(out, g_vcContext);
        int before = g_ctxShown;
        g_ctxShown = shown;
        if (shown >= 0 && shown != (int)g_vcDisplayable) {
            if (before != shown)
                LOG("context: cockpit context %u shows window %d, not the player's %u: the unit put it back t=%llu.%03llu",
                    g_vcContext, shown, g_vcDisplayable, T_ARGS(now_us()));
            pthread_mutex_lock(&g_switchLock);
            bool closed = g_switchClosed;
            pthread_mutex_unlock(&g_switchLock);
            /* At most ten times a session: never fight the unit in a loop. */
            if (g_reassert && !closed && g_ctxReasserts < 10u) {
                ++g_ctxReasserts;
                dmdt_pair(g_dmdtShow, g_dmdtSelect, "cluster switched to the player again (GAL_PLAYER_REASSERT)");
                g_ctxNextUs = now_us() + 5000000ULL;
            }
        } else if (shown >= 0 && before >= 0 && before != shown) {
            LOG("context: cockpit context %u shows the player's window %d again t=%llu.%03llu",
                g_vcContext, shown, T_ARGS(now_us()));
        }
    }
    g_ctxBusy = false;
    return NULL;
}

/* Render thread, about once a second. */
static void context_check_tick(uint64_t nowUs) {
    if (!g_switchDone || g_ctxBusy) return;
    if (g_ctxNextUs == 0) { g_ctxNextUs = nowUs + 5000000ULL; return; }
    if (nowUs < g_ctxNextUs) return;
    if (g_ctxThreadStarted) pthread_join(g_ctxThread, NULL);
    g_ctxThreadStarted = false;
    g_ctxNextUs = nowUs + 60000000ULL;
    g_ctxBusy = true;
    if (pthread_create(&g_ctxThread, NULL, context_check_thread, NULL) == 0) g_ctxThreadStarted = true;
    else g_ctxBusy = false;
}

/* Main thread, before the stock map is put back. */
static void context_check_stop() {
    if (g_ctxThreadStarted) pthread_join(g_ctxThread, NULL);
    g_ctxThreadStarted = false;
}
#endif

/* Decoder thread, at the phone's first keyframe; once per player. */
static void request_display_switch() {
    pthread_mutex_lock(&g_switchLock);
    if (!g_switchStarted && !g_switchClosed) {
        LOG("dmdt: switching the cluster at the first keyframe t=%llu.%03llu", T_ARGS(now_us()));
        if (pthread_create(&g_switchThread, NULL, display_switch_thread, NULL) == 0)
            g_switchStarted = true;
        else
            LOGE("dmdt: could not start the switch thread");
    }
    pthread_mutex_unlock(&g_switchLock);
}

/*
 * Main thread, on the way out: let a switch in progress finish, then put the
 * stock map back -- only if this player switched it. A player that never
 * got a keyframe has nothing to undo, and runs no dmdt at all.
 */
static void execute_final_commands() {
    pthread_mutex_lock(&g_switchLock);
    bool started = g_switchStarted;
    g_switchClosed = true;
    pthread_mutex_unlock(&g_switchLock);
    if (!started) return;
    pthread_join(g_switchThread, NULL);
    context_check_stop();
    dmdt_pair(g_dmdtRestore, g_dmdtSelect, "stock Kombi map restored");
}
#else
static void request_display_switch() {}
static void execute_final_commands() {}
static void context_check_tick(uint64_t) {}
#endif

// ---------------- Hardware decode (NvSS) ----------------
/*
 * GAL_PLAYER_DECODER=hw hands each complete H.264 access unit to the unit's
 * own decoder, libnvss_video.so: the library gal uses for the centre screen.
 * It decodes and scans the picture out straight onto a display-manager layer,
 * here displayable 3, the one context 70 puts on the cluster, so there is no
 * FFmpeg decode, YUV copy or GL draw (the software path costs 60-120 % of a
 * core). The structures are the ones gal itself fills before each call (open
 * parameters at this+8, the 12-byte stream config, the 64-byte attributes with
 * rectangles from byte 8 and visibility at 60/61), the same layout
 * aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto uses on
 * Tegra MU1438.
 *
 * Any failure before the first picture falls back to software decode in this
 * process. A failure after it marks hardware decode off for the rest of the
 * boot (NVSS_OFF_MARKER) and ends the player; the stock map is restored and
 * the next session uses software.
 */
#define NVSS_OFF_MARKER "/tmp/stream-player.hwdecode.off"
static bool g_hwDecoder = false;          /* GAL_PLAYER_DECODER=hw */
static unsigned g_nvssOutput = 1;         /* GAL_PLAYER_NVSS_OUTPUT: 1 as aberbic's cluster path; gal uses 0 (LVDS) for the centre screen */
static bool g_nvssActive = false;

#ifdef __QNX__
struct NvssOpenParams { uint32_t output, reserved; uint8_t priority, useLayer, layer, pad; uint32_t buffers, r2, r3; };
struct NvssStreamConfig { uint32_t width, height; float fps; };
struct NvssInput { void* data; uint32_t length; uint64_t timestamp; uint8_t flag, pad[7]; };
typedef char nvss_open_size_check[sizeof(NvssOpenParams) == 24 ? 1 : -1];
typedef char nvss_input_layout_check[offsetof(NvssInput, timestamp) == 8 ? 1 : -1];

static const uint32_t kNvssTimeout = 0x80000006u;   /* "try again": gal retries it (retryCount 5) */
static const int kNvssWaitMs = 35;
static const unsigned kNvssMaxRetries = 5;

static void* g_nvssHandle = NULL;
static int  (*p_kdInitializeNV)(void) = NULL;
static int  (*p_nvssOpen)(void**, const NvssOpenParams*) = NULL;
static int  (*p_nvssConfigure)(void*, const NvssStreamConfig*) = NULL;
static int  (*p_nvssGetAttribs)(void*, void*) = NULL;
static int  (*p_nvssSetAttribs)(void*, const void*) = NULL;
static int  (*p_nvssDecode)(void*, const NvssInput*, int) = NULL;
static int  (*p_nvssClose)(void*) = NULL;

static void put_u32(unsigned char* p, unsigned at, uint32_t v) { memcpy(p + at, &v, 4); }

static bool nvss_open(int frameW, int frameH, int windowW, int windowH,
                      int marginW, int marginH) {
    if (access(NVSS_OFF_MARKER, F_OK) == 0) {
        LOG("hwdecode: off for this boot (%s), using software decode", NVSS_OFF_MARKER);
        return false;
    }
    void* kd = dlopen("libKD.so", RTLD_NOW | RTLD_GLOBAL);
    void* nv = dlopen("libnvss_video.so", RTLD_NOW | RTLD_GLOBAL);
    if (!kd || !nv) {
        const char* e = dlerror();
        LOG("hwdecode: dlopen failed (%s), using software decode", e ? e : "unknown");
        return false;
    }
#define NVSS_LOAD(dst, lib, name) do { *(void**)(&(dst)) = dlsym(lib, name); \
        if (!(dst)) { LOG("hwdecode: %s missing, using software decode", name); return false; } } while (0)
    NVSS_LOAD(p_kdInitializeNV, kd, "kdInitializeNV");
    NVSS_LOAD(p_nvssOpen, nv, "NvSSVideoOpen");
    NVSS_LOAD(p_nvssConfigure, nv, "NvSSVideoStreamConfigure");
    NVSS_LOAD(p_nvssGetAttribs, nv, "NvSSVideoGetAttribs");
    NVSS_LOAD(p_nvssSetAttribs, nv, "NvSSVideoSetAttribs");
    NVSS_LOAD(p_nvssDecode, nv, "NvSSVideoDecode");
    NVSS_LOAD(p_nvssClose, nv, "NvSSVideoClose");
#undef NVSS_LOAD
    uint64_t began = now_us();
    int rc = p_kdInitializeNV();
    if (rc != 0) { LOG("hwdecode: kdInitializeNV=%d, using software decode", rc); return false; }

    /* As gal: priority 100, on a layer, 8 buffers. The layer is displayable 3. */
    NvssOpenParams op;
    memset(&op, 0, sizeof(op));
    op.output = g_nvssOutput; op.priority = 100; op.useLayer = 1; op.layer = 3; op.buffers = 8;
    rc = p_nvssOpen(&g_nvssHandle, &op);
    if (rc != 0 || !g_nvssHandle) { LOG("hwdecode: NvSSVideoOpen=0x%x, using software decode", (unsigned)rc); g_nvssHandle = NULL; return false; }

    int sourceX = marginW / 2;
    int sourceY = marginH / 2;
    int sourceW = frameW - marginW;
    int sourceH = frameH - marginH;
    if (sourceW <= 0 || sourceH <= 0) {
        LOG("hwdecode: invalid frame margins %dx%d in %dx%d; using software decode",
            marginW, marginH, frameW, frameH);
        p_nvssClose(g_nvssHandle);
        g_nvssHandle = NULL;
        return false;
    }
    NvssStreamConfig cfg = { (uint32_t)frameW, (uint32_t)frameH, 30.0f };
    rc = p_nvssConfigure(g_nvssHandle, &cfg);
    if (rc != 0) { LOG("hwdecode: NvSSVideoStreamConfigure=0x%x, using software decode", (unsigned)rc); p_nvssClose(g_nvssHandle); g_nvssHandle = NULL; return false; }

    unsigned char attrs[64];
    memset(attrs, 0, sizeof(attrs));
    if (p_nvssGetAttribs(g_nvssHandle, attrs) == 0) {
        /* Crop the margins to the requested window, and show the layer. */
        attrs[8] = 1;
        put_u32(attrs, 12, (uint32_t)sourceX); put_u32(attrs, 16, (uint32_t)sourceY);
        put_u32(attrs, 20, (uint32_t)sourceW); put_u32(attrs, 24, (uint32_t)sourceH);
        put_u32(attrs, 28, 0); put_u32(attrs, 32, 0);
        put_u32(attrs, 36, (uint32_t)windowW); put_u32(attrs, 40, (uint32_t)windowH);
        attrs[60] = 1; attrs[61] = 0;
        rc = p_nvssSetAttribs(g_nvssHandle, attrs);
        if (rc != 0) {
            if (frameW == 800 && frameH == 480) {
                LOG("hwdecode: NvSSVideoSetAttribs=0x%x (continuing with the defaults)", (unsigned)rc);
            } else {
                LOG("hwdecode: NvSSVideoSetAttribs=0x%x, using software decode", (unsigned)rc);
                p_nvssClose(g_nvssHandle);
                g_nvssHandle = NULL;
                return false;
            }
        }
    } else {
        if (frameW == 800 && frameH == 480) {
            LOG("hwdecode: NvSSVideoGetAttribs failed (continuing with the defaults)");
        } else {
            LOG("hwdecode: NvSSVideoGetAttribs failed, using software decode");
            p_nvssClose(g_nvssHandle);
            g_nvssHandle = NULL;
            return false;
        }
    }
    if (frameW == 800 && frameH == 480) {
        LOG("hwdecode: NvSS decoder ready on displayable 3 (output=%u, %dx%d) in %llu ms",
            g_nvssOutput, frameW, frameH,
            (unsigned long long)((now_us() - began) / 1000ULL));
    } else {
        LOG("hwdecode: NvSS decoder ready on displayable 3 (output=%u, frame=%dx%d crop=%d,%d %dx%d window=%dx%d) in %llu ms",
            g_nvssOutput, frameW, frameH, sourceX, sourceY, sourceW, sourceH,
            windowW, windowH, (unsigned long long)((now_us() - began) / 1000ULL));
    }
    g_nvssActive = true;
    return true;
}

/* 0 = decoded, <0 = failed. */
static int nvss_decode(const uint8_t* data, int size) {
    NvssInput in;
    memset(&in, 0, sizeof(in));
    in.data = (void*)data; in.length = (uint32_t)size; in.timestamp = UINT64_MAX;   /* no timestamp scheduling */
    unsigned retries = 0;
    int rc;
    for (;;) {
        rc = p_nvssDecode(g_nvssHandle, &in, kNvssWaitMs);
        if ((uint32_t)rc != kNvssTimeout || retries >= kNvssMaxRetries || !g_running) break;
        retries++;
        usleep(1000);
    }
    if (rc != 0) {
        LOGE("hwdecode: NvSSVideoDecode=0x%x after %u retries", (unsigned)rc, retries);
        return -1;
    }
    return 0;
}

static void nvss_close() {
    if (g_nvssHandle) {
        int rc = p_nvssClose(g_nvssHandle);
        LOG("hwdecode: decoder closed (%d)", rc);
        g_nvssHandle = NULL;
    }
    g_nvssActive = false;
}

static void nvss_disable_for_boot(const char* why) {
    int fd = open(NVSS_OFF_MARKER, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd >= 0) { (void)write(fd, why, strlen(why)); close(fd); }
    LOGE("hwdecode: switched off for this boot (%s)", why);
}
#else
static bool nvss_open(int, int, int, int, int, int) { return false; }
static int nvss_decode(const uint8_t*, int) { return -1; }
static void nvss_close() {}
static void nvss_disable_for_boot(const char*) {}
#endif

// ---------------- Hardware decode into memory (NvMedia) ----------------
/*
 * GAL_PLAYER_DECODER=hw on units whose cockpit is not a display output of
 * its own (VW, Skoda, SEAT: NvSS above fails there with "Invalid display
 * width/height"). libnvss_video.so sits on two lower libraries, libnvparser.so
 * (H.264 parser with callbacks) and libnvmedia.so (decoder and picture
 * surfaces). This uses those two the way libnvss_video.so does, without its
 * mixer and output: every picture is decoded into a surface, the surface is
 * locked and its three planes are copied into the frame pool, and from there
 * everything is the software path (drawing, pacing, the cockpit switch).
 *
 * Every offset was read from libnvss_video.so of MHI2_ER_VWG13_P4521
 * (BeginSequence 0x46a0, DecodePicture 0x506c, decoder set-up 0x411c) and
 * proved on that car with scripts/experiments/nvprobe.c: 800x480 at about
 * 3 ms of processor time a picture, pixels identical to a reference decode.
 *
 * A failure before the stream starts leaves software decode. A failure in
 * the stream marks hardware decode off for the rest of the boot
 * (NVSS_OFF_MARKER) and ends the player, as the NvSS path does.
 */
static bool g_nvmActive = false;
static bool g_nvmWanted = false;         /* hw asked and NvSS could not draw to this cockpit */
/* GAL_PLAYER_HW_HD=1: decode a 720p or 1080p frame into memory too. Off by
 * default: on a Skoda P4526 at 720p, every time the centre screen took
 * Android Auto back, gal's own decoder failed (NvSSVideoDecode
 * BUFFER_NOT_CONSUMED) and the centre screen stayed black (#125, #145; 17 of
 * 17 restarts in the owner's logs). Not seen at 800x480 (Golf P4521) or with
 * software decode. The NvSS path above (Audi, drawing straight to the
 * cockpit) is not affected. */
static bool g_hwHd = false;
#ifdef __QNX__
#define NVM_MAX_PICS 24
struct NvmPic { void* surface; int refs; };
static void* (*p_nvmDeviceCreate)(void) = NULL;
static void  (*p_nvmDeviceDestroy)(void*) = NULL;
static void* (*p_nvmDecoderCreate)(int, uint16_t, uint16_t, uint16_t, uint32_t, uint32_t) = NULL;
static void  (*p_nvmDecoderDestroy)(void*) = NULL;
static int   (*p_nvmDecoderRender)(void*, void*, const void*, uint32_t, const void*) = NULL;
static void* (*p_nvmSurfaceCreate)(void*, int, uint16_t, uint16_t) = NULL;
static void  (*p_nvmSurfaceDestroy)(void*) = NULL;
static int   (*p_nvmSurfaceLock)(void*, void*) = NULL;
static void  (*p_nvmSurfaceUnlock)(void*) = NULL;
static void* (*p_nvpCreate)(void*) = NULL;
static void  (*p_nvpDestroy)(void*) = NULL;
static int   (*p_nvpParse)(void*, void*) = NULL;
static int   (*p_nvpSetAttribute)(void*, int, int, void*) = NULL;

static void* g_nvmDevice = NULL;
static void* g_nvmDecoder = NULL;
static void* g_nvmParser = NULL;
static NvmPic g_nvmPics[NVM_MAX_PICS];
static int g_nvmPicCount = 0;
static unsigned g_nvmCodedW = 0, g_nvmCodedH = 0, g_nvmW = 0, g_nvmH = 0;
static bool g_nvmFull = false, g_nvmBt709 = false;
static bool g_nvmFailed = false;
static bool g_nvmWarm = false;          /* the first picture is not shown, as in software */
static int g_nvmPacketBytes = 0;
static bool g_nvmPacketKey = false;
static uint64_t g_nvmPacketStartUs = 0;
static uint64_t g_nvmPublished = 0;

static uint32_t nvm_r32(const void* p, unsigned at) { uint32_t v; memcpy(&v, (const uint8_t*)p + at, 4); return v; }
static uint16_t nvm_r16(const void* p, unsigned at) { uint16_t v; memcpy(&v, (const uint8_t*)p + at, 2); return v; }
static uint8_t  nvm_r8(const void* p, unsigned at) { return ((const uint8_t*)p)[at]; }
static void nvm_w32(uint8_t* p, unsigned at, uint32_t v) { memcpy(p + at, &v, 4); }
static void nvm_w16(uint8_t* p, unsigned at, uint16_t v) { memcpy(p + at, &v, 2); }

static void nvm_free_pictures() {
    if (g_nvmDecoder) { p_nvmDecoderDestroy(g_nvmDecoder); g_nvmDecoder = NULL; }
    for (int i = 0; i < g_nvmPicCount; ++i)
        if (g_nvmPics[i].surface) p_nvmSurfaceDestroy(g_nvmPics[i].surface);
    memset(g_nvmPics, 0, sizeof(g_nvmPics));
    g_nvmPicCount = 0;
}

/* Returns how many decode buffers the stream needs, 0 to refuse it. */
static int nvm_cb_begin(void*, const void* seq) {
    int codec = (int)nvm_r32(seq, 0x00);
    int buffers = (int)nvm_r32(seq, 0x10);
    unsigned dw = nvm_r32(seq, 0x18), dh = nvm_r32(seq, 0x1c);
    unsigned w = nvm_r32(seq, 0x20), h = nvm_r32(seq, 0x24);
    unsigned chroma = nvm_r8(seq, 0x30);
    unsigned fullRange = nvm_r8(seq, 0x44);
    unsigned matrix = nvm_r32(seq, 0x50);
    uint32_t maxBitstream = nvm_r32(seq, 0x58);
    if (codec != 4 || w == 0 || h == 0 || w > 1920 || h > 1088 || chroma > 1) {
        LOG("hwdecode: stream not usable (codec %d, %ux%u, chroma %u)", codec, w, h, chroma);
        g_nvmFailed = true;
        return 0;
    }
    if (dw == 0 || dw > w) dw = w;
    if (dh == 0 || dh > h) dh = h;
    if (g_nvmDecoder && w == g_nvmCodedW && h == g_nvmCodedH) { g_nvmW = dw; g_nvmH = dh; return buffers; }
    nvm_free_pictures();
    g_nvmCodedW = w; g_nvmCodedH = h; g_nvmW = dw; g_nvmH = dh;
    g_nvmFull = fullRange != 0;
    g_nvmBt709 = matrix == 1 || ((matrix == 2 || matrix == 3) && dh >= 720);
    LOG("colour: stream range %d, matrix %u (%ux%u); drawn as %s", g_nvmFull ? 2 : 1, matrix, dw, dh,
        !g_colorAuto ? "full-range BT.601 (GAL_PLAYER_COLOR=old)" :
        g_nvmFull ? (g_nvmBt709 ? "full-range BT.709" : "full-range BT.601") :
                    (g_nvmBt709 ? "limited-range BT.709" : "limited-range BT.601"));

    uint16_t refs = 0;
    if (buffers > 0) { int r = buffers - 1; if (r > 16) r = 16; refs = (uint16_t)r; }
    uint64_t began = now_us();
    g_nvmDecoder = p_nvmDecoderCreate(0, (uint16_t)w, (uint16_t)h, refs, maxBitstream, 3);
    if (!g_nvmDecoder) { LOG("hwdecode: NvMediaVideoDecoderCreate failed (%ux%u, refs %u)", w, h, refs); g_nvmFailed = true; return 0; }
    int want = buffers + 3;
    if (want > NVM_MAX_PICS) want = NVM_MAX_PICS;
    if (want < 4) want = 4;
    for (g_nvmPicCount = 0; g_nvmPicCount < want; ++g_nvmPicCount) {
        void* surface = p_nvmSurfaceCreate(g_nvmDevice, 0, (uint16_t)((w + 15) & 0xfff0), (uint16_t)((h + 15) & 0xfff0));
        if (!surface) break;
        g_nvmPics[g_nvmPicCount].surface = surface;
        g_nvmPics[g_nvmPicCount].refs = 0;
    }
    if (g_nvmPicCount < buffers + 1) {
        LOG("hwdecode: only %d of %d picture surfaces", g_nvmPicCount, want);
        g_nvmFailed = true;
        return 0;
    }
    LOG("hwdecode: decoder ready in memory (%ux%u shown %ux%u, %d reference pictures, %d surfaces) in %llu ms",
        w, h, dw, dh, refs, g_nvmPicCount, (unsigned long long)((now_us() - began) / 1000ULL));
    return buffers;
}

static int nvm_cb_alloc(void*, void** out) {
    *out = NULL;
    for (int i = 0; i < g_nvmPicCount; ++i)
        if (g_nvmPics[i].refs == 0) { g_nvmPics[i].refs = 1; *out = &g_nvmPics[i]; return 1; }
    LOG("hwdecode: no free picture surface");
    g_nvmFailed = true;
    return 0;
}
static void nvm_cb_addref(void*, void* p) { if (p) ((NvmPic*)p)->refs++; }
static void nvm_cb_release(void*, void* p) { if (p && ((NvmPic*)p)->refs > 0) ((NvmPic*)p)->refs--; }
static void nvm_cb_nalu(void*, const uint8_t*, int) {}

/* The decoder's picture description, field by field as libnvss_video.so
 * fills it (0x50e0..0x52a8) from the parser's picture data. */
static int nvm_cb_decode(void*, void* pd) {
    static uint8_t pic[0x2d8];
    static const struct { uint16_t to, from; uint8_t byteSource; } kBytes[] = {
        {0x10,0x0c,0},{0x11,0x10,0},{0x12,0x88,0},{0x13,0xb6,1},{0x14,0xb7,1},{0x15,0xa4,0},{0x16,0xa8,0},
        {0x17,0x80,0},{0x18,0xb5,1},{0x19,0xba,1},{0x1a,0xbb,1},{0x1b,0xac,0},{0x1c,0x9c,0},{0x1d,0xa0,0},
        {0x1e,0x70,0},{0x1f,0x74,0},{0x20,0x78,0},{0x21,0x7c,0},{0x22,0x84,0},{0x23,0xb8,1},{0x24,0xb9,1},
        {0x25,0xb4,1},{0x26,0xb0,0},{0x27,0xca,1},{0x28,0xcb,1},{0x34,0xc8,1},{0x35,0xc9,1},
    };
    NvmPic* cur = (NvmPic*)(uintptr_t)nvm_r32(pd, 0x08);
    if (!cur || !cur->surface || !g_nvmDecoder) { g_nvmFailed = true; return 0; }
    memset(pic, 0, sizeof(pic));
    nvm_w32(pic, 0x00, nvm_r32(pd, 0xc0));
    nvm_w32(pic, 0x04, nvm_r32(pd, 0xc4));
    nvm_w32(pic, 0x08, nvm_r32(pd, 0x24));
    nvm_w16(pic, 0x0c, nvm_r16(pd, 0x2c));
    nvm_w16(pic, 0x0e, nvm_r16(pd, 0xbc));
    for (unsigned i = 0; i < sizeof(kBytes) / sizeof(kBytes[0]); ++i)
        pic[kBytes[i].to] = kBytes[i].byteSource ? nvm_r8(pd, kBytes[i].from) : (uint8_t)nvm_r32(pd, kBytes[i].from);
    nvm_w32(pic, 0x2c, nvm_r32(pd, 0xd0));
    nvm_w32(pic, 0x30, nvm_r32(pd, 0xd4));
    memcpy(pic + 0x36, (const uint8_t*)pd + 0x660, 0x60);
    memcpy(pic + 0x96, (const uint8_t*)pd + 0x6c0, 0x80);
    for (unsigned i = 0; i < 16; ++i) {
        unsigned from = 0xe0 + i * 0x1c, to = 0x118 + i * 0x1c;
        NvmPic* ref = (NvmPic*)(uintptr_t)nvm_r32(pd, from);
        uint32_t flags = nvm_r32(pd, from + 0x10);
        nvm_w32(pic, to + 0x00, ref ? (uint32_t)(uintptr_t)ref->surface : 0u);
        nvm_w32(pic, to + 0x04, nvm_r32(pd, from + 0x08));
        nvm_w32(pic, to + 0x08, flags & 1u);
        nvm_w32(pic, to + 0x0c, (flags >> 1) & 1u);
        nvm_w32(pic, to + 0x10, nvm_r32(pd, from + 0x14));
        nvm_w32(pic, to + 0x14, nvm_r32(pd, from + 0x18));
        nvm_w16(pic, to + 0x18, (uint16_t)nvm_r32(pd, from + 0x04));
    }
    uint32_t bitstream[2];
    bitstream[0] = nvm_r32(pd, 0x38);
    bitstream[1] = nvm_r32(pd, 0x34);
    int rc = p_nvmDecoderRender(g_nvmDecoder, cur->surface, pic, 1, bitstream);
    if (rc != 0) { LOG("hwdecode: NvMediaVideoDecoderRender=0x%x", (unsigned)rc); g_nvmFailed = true; return 0; }
    return 1;
}

/* A decoded picture: copy its planes into the frame pool, as the software
 * path does from an AVFrame. Lock map: {width, height, Y, Y pitch, U, U
 * pitch, V, V pitch}; the pitch of an 800 wide picture is 832. */
static int nvm_cb_display(void*, void* p, long long) {
    NvmPic* picture = (NvmPic*)p;
    if (!picture || !picture->surface) return 1;
    if (!g_nvmWarm) {
        g_nvmWarm = true;
        LOG("decoder: warmup frame consumed; rendering next decoded frame.");
        return 1;
    }
    uint32_t map[64];
    memset(map, 0, sizeof(map));
    int rc = p_nvmSurfaceLock(picture->surface, map);
    if (rc != 0) { LOG("hwdecode: NvMediaVideoSurfaceLock=0x%x", (unsigned)rc); g_nvmFailed = true; return 0; }
    int w = (int)g_nvmW, h = (int)g_nvmH;
    const uint8_t* srcY = (const uint8_t*)(uintptr_t)map[2];
    const uint8_t* srcU = (const uint8_t*)(uintptr_t)map[4];
    const uint8_t* srcV = (const uint8_t*)(uintptr_t)map[6];
    uint32_t pitchY = map[3], pitchU = map[5], pitchV = map[7];
    if (!srcY || !srcU || !srcV || (int)map[0] < w || (int)map[1] < h ||
        pitchY < (uint32_t)w || pitchU < (uint32_t)(w / 2) || pitchV < (uint32_t)(w / 2) || pitchY > 4096u) {
        LOG("hwdecode: unexpected picture layout (%ux%u, planes %p %p %p, pitches %u %u %u)",
            (unsigned)map[0], (unsigned)map[1], (const void*)srcY, (const void*)srcU, (const void*)srcV,
            (unsigned)pitchY, (unsigned)pitchU, (unsigned)pitchV);
        p_nvmSurfaceUnlock(picture->surface);
        g_nvmFailed = true;
        return 0;
    }
    pthread_mutex_lock(&g_frameMutex);
    RGBABuffer* buf = g_framePool.getWriteBuffer(w, h);
    buf->packetBytes = g_nvmPacketBytes;
    buf->isKeyframe = g_nvmPacketKey;
    buf->colorFull = g_nvmFull;
    buf->colorBt709 = g_nvmBt709;
    uint8_t* dstY = buf->pixels;
    uint8_t* dstU = dstY + (w * h);
    uint8_t* dstV = dstU + ((w / 2) * (h / 2));
    for (int y = 0; y < h; ++y) memcpy(dstY + y * w, srcY + (size_t)y * pitchY, w);
    if ((g_decodedFrameCount & 31u) == 0) {
        uint64_t sum = 0, count = 0;
        for (int y = 8; y < h; y += 16)
            for (int x = 8; x < w; x += 16, ++count) sum += dstY[y * w + x];
        g_lastLuma = count ? (unsigned)(sum / count) : 0u;
    }
    for (int y = 0; y < h / 2; ++y) memcpy(dstU + y * (w / 2), srcU + (size_t)y * pitchU, w / 2);
    for (int y = 0; y < h / 2; ++y) memcpy(dstV + y * (w / 2), srcV + (size_t)y * pitchV, w / 2);
    g_framePool.publishWrite();
    g_newFrameReady = true;
    g_decodedFrameCount++;
    g_lastDecodeDurationUs = now_us() - g_nvmPacketStartUs;
    pthread_cond_signal(&g_frameCond);
    pthread_mutex_unlock(&g_frameMutex);
    p_nvmSurfaceUnlock(picture->surface);
    if (g_nvmPublished++ == 0)
        LOG("hwdecode: first picture from the hardware decoder (%dx%d, pitches %u/%u) t=%llu.%03llu",
            w, h, (unsigned)pitchY, (unsigned)pitchU, T_ARGS(now_us()));
    return 1;
}

/* Loads the two libraries and makes the parser. The decoder itself is made
 * when the stream's first sequence header arrives. */
static bool nvm_open() {
    if (access(NVSS_OFF_MARKER, F_OK) == 0) {
        LOG("hwdecode: off for this boot (%s), using software decode", NVSS_OFF_MARKER);
        return false;
    }
    void* media = dlopen("libnvmedia.so", RTLD_NOW | RTLD_GLOBAL);
    void* parserLib = dlopen("libnvparser.so", RTLD_NOW | RTLD_GLOBAL);
    if (!media || !parserLib) {
        const char* e = dlerror();
        LOG("hwdecode: dlopen failed (%s), using software decode", e ? e : "unknown");
        return false;
    }
#define NVM_LOAD(dst, lib, name) do { *(void**)(&(dst)) = dlsym(lib, name); \
        if (!(dst)) { LOG("hwdecode: %s missing, using software decode", name); return false; } } while (0)
    NVM_LOAD(p_nvmDeviceCreate, media, "NvMediaDeviceCreate");
    NVM_LOAD(p_nvmDeviceDestroy, media, "NvMediaDeviceDestroy");
    NVM_LOAD(p_nvmDecoderCreate, media, "NvMediaVideoDecoderCreate");
    NVM_LOAD(p_nvmDecoderDestroy, media, "NvMediaVideoDecoderDestroy");
    NVM_LOAD(p_nvmDecoderRender, media, "NvMediaVideoDecoderRender");
    NVM_LOAD(p_nvmSurfaceCreate, media, "NvMediaVideoSurfaceCreate");
    NVM_LOAD(p_nvmSurfaceDestroy, media, "NvMediaVideoSurfaceDestroy");
    NVM_LOAD(p_nvmSurfaceLock, media, "NvMediaVideoSurfaceLock");
    NVM_LOAD(p_nvmSurfaceUnlock, media, "NvMediaVideoSurfaceUnlock");
    NVM_LOAD(p_nvpCreate, parserLib, "video_parser_create");
    NVM_LOAD(p_nvpDestroy, parserLib, "video_parser_destroy");
    NVM_LOAD(p_nvpParse, parserLib, "video_parser_parse");
    NVM_LOAD(p_nvpSetAttribute, parserLib, "video_parser_set_attribute");
#undef NVM_LOAD
    g_nvmDevice = p_nvmDeviceCreate();
    if (!g_nvmDevice) { LOG("hwdecode: NvMediaDeviceCreate failed, using software decode"); return false; }
    /* As libnvss_video.so at 0x5944: seven callbacks, then {callbacks,
     * context, clock rate, error threshold, H.264}. */
    static void* callbacks[12];
    static uint32_t params[16];
    callbacks[0] = (void*)nvm_cb_begin;  callbacks[1] = (void*)nvm_cb_decode;  callbacks[2] = (void*)nvm_cb_display;
    callbacks[3] = (void*)nvm_cb_nalu;   callbacks[4] = (void*)nvm_cb_alloc;   callbacks[5] = (void*)nvm_cb_release;
    callbacks[6] = (void*)nvm_cb_addref;
    params[0] = (uint32_t)(uintptr_t)callbacks; params[1] = (uint32_t)(uintptr_t)params;
    params[2] = 1000000u; params[3] = 50u; params[4] = 4u;
    g_nvmParser = p_nvpCreate(params);
    if (!g_nvmParser) {
        LOG("hwdecode: video_parser_create failed, using software decode");
        p_nvmDeviceDestroy(g_nvmDevice); g_nvmDevice = NULL;
        return false;
    }
    uint8_t one = 1;
    p_nvpSetAttribute(g_nvmParser, 4, 1, &one);
    LOG("hwdecode: the unit's decoder is used, decoding into memory (libnvmedia.so)");
    g_nvmActive = true;
    return true;
}

/* One access unit. false = the hardware decoder failed. */
static bool nvm_decode(const uint8_t* data, int size, bool key) {
    static uint32_t packet[16];
    memset(packet, 0, sizeof(packet));
    packet[0] = (uint32_t)(uintptr_t)data;
    packet[1] = (uint32_t)size;
    g_nvmPacketBytes = size;
    g_nvmPacketKey = key;
    g_nvmPacketStartUs = now_us();
    int ok = p_nvpParse(g_nvmParser, packet);
    if (!ok && !g_nvmFailed) { LOG("hwdecode: the parser refused %d bytes", size); g_nvmFailed = true; }
    return !g_nvmFailed;
}

static void nvm_close() {
    if (g_nvmParser) { p_nvpDestroy(g_nvmParser); g_nvmParser = NULL; }
    if (g_nvmDevice) {
        nvm_free_pictures();
        p_nvmDeviceDestroy(g_nvmDevice); g_nvmDevice = NULL;
        LOG("hwdecode: decoder closed (%llu pictures)", (unsigned long long)g_nvmPublished);
    }
    g_nvmActive = false;
}
#else
static bool nvm_open() { return false; }
static bool nvm_decode(const uint8_t*, int, bool) { return false; }
static void nvm_close() {}
#endif

static void write_ack();
/*
 * GAL_ACK_EVERY_FRAME=1 (AMDFX60's 1.4.0, as an opt-in here): every frame the
 * phone sends is ACKed exactly once -- when its picture is drawn, when a
 * newer picture replaces it before it is drawn, or at once when it gives no
 * picture (before the first keyframe, the warm-up frame, a decode error, or
 * bytes skipped to reach a keyframe). The hook then stops presuming frames
 * dropped, which had let the phone queue seconds of frames in front of a
 * slow 720p decoder (pepsonEL's Skoda, #125: 1-1.5 s behind).
 *
 * In this mode the hook ends every frame with an access unit delimiter
 * (00 00 00 01 09 f0), and the phone's own frames carry none, so frames are
 * counted by delimiters in the bytes the decoder has consumed. ack_settle()
 * ACKs everything consumed except the one picture still waiting to be drawn,
 * so it can never ACK a frame that has not arrived. Off (the default) the
 * player ACKs only drawn pictures, as up to v1.2.8, and the hook makes up
 * the rest.
 */
static bool g_ackEveryFrame = false;
static pthread_mutex_t g_ackLock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_ackConsumed = 0;     /* g_ackLock: frames whose delimiter has been consumed */
static uint64_t g_ackSent = 0;         /* g_ackLock */
static unsigned g_audZeros = 0;        /* decoder thread: delimiter scanner state */
static void ack_count_bytes(const uint8_t* p, size_t n) {
    if (!g_ackEveryFrame) return;
    unsigned found = 0;
    for (size_t i = 0; i < n; ++i) {
        uint8_t b = p[i];
        if (g_audZeros >= 3u) {           /* after 00 00 01 */
            g_audZeros = 0;
            if ((b & 0x1f) == 9) { ++found; continue; }
        }
        if (b == 0) { g_audZeros = g_audZeros >= 2u ? 2u : g_audZeros + 1u; continue; }
        g_audZeros = (b == 1 && g_audZeros >= 2u) ? 3u : 0u;
    }
    if (found) {
        pthread_mutex_lock(&g_ackLock);
        g_ackConsumed += found;
        pthread_mutex_unlock(&g_ackLock);
    }
}
static void ack_settle(bool pictureWaiting);

static void crash_signal_handler(int sig) {
    /* First, with calls that are safe in a signal handler: the next start,
     * until reboot, decodes without NEON (see main). One more NEON routine
     * the QNX kernel stops then costs one restart of the player, not the map. */
    if (sig == SIGBUS || sig == SIGILL || sig == SIGSEGV) {
        int fd = open(kNoNeonMarker, O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (fd >= 0) {
            static const char msg[] = "the player crashed; NEON off until reboot\n";
            if (write(fd, msg, sizeof(msg) - 1) < 0) { /* nothing to do about it here */ }
            close(fd);
        }
    }
    fprintf(stderr, "\n[stream-player CRASH] Caught fatal signal %d! Emergency restoring the stock cluster map...\n", sig);
#ifdef __QNX__
    if (g_dmdtCrashCmd[0]) system(g_dmdtCrashCmd);
#endif
    signal(sig, SIG_DFL);
    raise(sig);
}

static void signal_handler(int sig) {
    (void)sig;
    g_running = false;
    pthread_cond_broadcast(&g_frameCond);
    int s = g_streamSock;
    if (s >= 0) {
        shutdown(s, SHUT_RDWR);
    }
#ifndef __QNX__
    if (g_dumpVideoPipe) {
        pclose(g_dumpVideoPipe);
        g_dumpVideoPipe = NULL;
    }
#endif
}

// ---------------- Shader Compilation & Setup ----------------
static void check_shader(GLuint shader, const char* name) {
    GLint status = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (!status) {
        char log[512] = {0};
        glGetShaderInfoLog(shader, sizeof(log)-1, NULL, log);
        fprintf(stderr, "GL: shader '%s' compile failed: %s\n", name, log);
    } else {
        LOG("GL: shader '%s' compiled ok", name);
    }
}

static void check_program(GLuint prog, const char* name) {
    GLint status = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (!status) {
        char log[512] = {0};
        glGetProgramInfoLog(prog, sizeof(log)-1, NULL, log);
        fprintf(stderr, "GL: program '%s' link failed: %s\n", name, log);
    } else {
        LOG("GL: program '%s' linked ok", name);
    }
}

void InitGL() {
    GLuint vs = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vs, 1, &vertexShaderSource, NULL);
    glCompileShader(vs);
    check_shader(vs, "vert-main");

    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fs, 1, &fragmentShaderSource, NULL);
    glCompileShader(fs);
    check_shader(fs, "frag-main");

    g_programObject = glCreateProgram();
    glAttachShader(g_programObject, vs);
    glAttachShader(g_programObject, fs);
    glLinkProgram(g_programObject);
    check_program(g_programObject, "main");

    g_posAttr = glGetAttribLocation(g_programObject, "position");
    g_texAttr = glGetAttribLocation(g_programObject, "texCoord");
    g_texLocY = glGetUniformLocation(g_programObject, "texY");
    g_texLocU = glGetUniformLocation(g_programObject, "texU");
    g_texLocV = glGetUniformLocation(g_programObject, "texV");
    g_rangeLoc = glGetUniformLocation(g_programObject, "range");
    g_matrixLoc = glGetUniformLocation(g_programObject, "matrix");
    LOG("GL: attrib locations: pos=%d tex=%d", g_posAttr, g_texAttr);

    GLint linkStatus = 0;
    glGetProgramiv(g_programObject, GL_LINK_STATUS, &linkStatus);
    if (linkStatus) {
        g_useShader = true;
        LOG("GL: GLES2 shader pipeline ACTIVE");
    } else {
        LOGE("GL: shader link failed, probing for hardware blit extension...");
    }

#ifdef __QNX__
    g_pfnDrawTextureNV = (PFNGLDRAWTEXTURENVPROC)eglGetProcAddress("glDrawTextureNV");
    if (g_pfnDrawTextureNV) {
        LOG("GL: GL_NV_draw_texture hardware blitter available at %p", (void*)g_pfnDrawTextureNV);
    } else {
        LOG("GL: GL_NV_draw_texture NOT available");
    }

    if (!g_useShader && !g_pfnDrawTextureNV) {
        LOGE("FATAL: no rendering path (shader link failed AND glDrawTextureNV not found)");
        GLint numBinFmt = 0;
        glGetIntegerv(0x8DF9 /* GL_NUM_SHADER_BINARY_FORMATS */, &numBinFmt);
        LOGE("FATAL: GL_NUM_SHADER_BINARY_FORMATS = %d", numBinFmt);
    }
#endif

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    GLuint texs[3];
    glGenTextures(3, texs);
    g_texY = texs[0]; g_texU = texs[1]; g_texV = texs[2];
    for (int i=0; i<3; ++i) {
        glBindTexture(GL_TEXTURE_2D, texs[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    glViewport(0, 0, windowWidth, windowHeight);
    glClearColor(backgroundColor[0], backgroundColor[1], backgroundColor[2], backgroundColor[3]);
    LOG("GL: hardware RGBA texture & shaders initialized successfully");
}

// ---------------- H.264 Video Decoder Thread ----------------
/*
 * The hook opens its socket before it starts the player, so the first connect
 * succeeded for every player on the car. A retry is for the case where it
 * does not: once a second, and only while gal is still our parent -- a player
 * whose gal is gone has nobody to connect to.
 */
static bool connect_retry_allowed() {
    if (!g_running) return false;
    if (g_parentPid > 1 && getppid() != g_parentPid) {
        LOG("socket: gal (pid %ld) is gone; exiting", (long)g_parentPid);
        g_running = false;
        pthread_cond_broadcast(&g_frameCond);
        return false;
    }
    sleep(1);
    return g_running;
}

/* Reader side: drain the socket into g_rb until it closes or the buffer fills. */
/*
 * The last SPS and PPS the stream carried. CarPlay sends them once, so a
 * parser restarted at a keyframe would never see them again: "non-existing
 * PPS 0 referenced" at every frame from then on (a Leon on beta14, 11194
 * lines in 11 minutes). Only the parser loses them, the decoder keeps its own.
 */
static uint8_t g_paramSets[1024];
static size_t  g_paramSetsLen = 0;

static void remember_param_sets(const uint8_t* p, size_t n) {
    for (size_t i = 0; i + 3 < n; i++) {
        if (p[i] != 0 || p[i + 1] != 0 || p[i + 2] != 1) continue;
        int type = p[i + 3] & 0x1f;
        if (type != 7 && type != 8) continue;
        size_t end = i + 3;
        while (end + 2 < n && !(p[end] == 0 && p[end + 1] == 0 && p[end + 2] <= 1)) end++;
        if (end + 2 >= n) return; /* runs past this read; the next set will do */
        size_t len = end - i;
        if (type == 7) g_paramSetsLen = 0; /* a new SPS starts a new set */
        if (g_paramSetsLen + len <= sizeof g_paramSets) {
            memcpy(g_paramSets + g_paramSetsLen, p + i, len);
            g_paramSetsLen += len;
        }
        i = end - 1;
    }
}

/*
 * Centre-screen restarts (#125, Skoda P4526). With GAL_DEBUG_PRIMARY=1 or
 * GAL_PRIMARY_RESTART_PAUSE_MS the hook writes "<start> <session> <pause_ms>"
 * to /tmp/clustermap-primary-start each time the centre screen's video
 * starts. The decoder thread looks every 50 ms: it logs the start with the
 * unit's free memory, and stops decoding for pause_ms (sent only for
 * restarts) so the centre decoder starts with the CPU to itself. The phone
 * sends at most the ACK window meanwhile, so nothing is dropped.
 */
static void* primary_mem_thread(void* arg) {
    (void)arg;
#ifdef __QNX__
    FILE* p = popen("pidin info 2>/dev/null", "r");
    if (p) {
        char line[256];
        bool first = true;
        while (fgets(line, sizeof(line), p)) {
            if (first && !strstr(line, "FreeMem:")) {
                /* Format not seen on these units yet: keep the first line. */
                char* nl = strpbrk(line, "\r\n");
                if (nl) *nl = '\0';
                LOG("primary: pidin info: %s", line);
            }
            first = false;
            char* m = strstr(line, "FreeMem:");
            if (m) {
                char* end = strpbrk(m, " \r\n");
                if (end) *end = '\0';
                LOG("primary: unit %s t=%llu.%03llu", m, T_ARGS(now_us()));
                break;
            }
        }
        pclose(p);
    }
#endif
    return NULL;
}

static void primary_restart_check() {
    static uint64_t s_nextUs = 0;
    static int s_lastStart = -1;
    if (!g_primaryWatch) return;
    uint64_t now = now_us();
    if (now < s_nextUs) return;
    s_nextUs = now + 50000ULL;
    FILE* f = fopen("/tmp/clustermap-primary-start", "r");
    if (!f) return;
    int start = 0, session = 0;
    unsigned pauseMs = 0;
    int got = fscanf(f, "%d %d %u", &start, &session, &pauseMs);
    fclose(f);
    if (got != 3 || start == s_lastStart) return;
    bool first = s_lastStart < 0;
    s_lastStart = start;
    if (first) return; /* that start came before this player */
    LOG("primary: centre screen video started (start %d, session %d), %llu pictures decoded so far t=%llu.%03llu",
        start, session, (unsigned long long)g_decodedFrameCount, T_ARGS(now));
    pthread_t t;
    if (pthread_create(&t, NULL, primary_mem_thread, NULL) == 0) pthread_detach(t);
    if (pauseMs > 0u && pauseMs <= 10000u) {
        uint64_t until = now + (uint64_t)pauseMs * 1000ULL;
        while (g_running && now_us() < until) usleep(20000);
        LOG("primary: decoding again after a %u ms pause (GAL_PRIMARY_RESTART_PAUSE_MS) t=%llu.%03llu",
            pauseMs, T_ARGS(now_us()));
    }
}

static void* ReaderThreadFunc(void* arg) {
    int sock = (int)(intptr_t)arg;
    uint8_t* tmp = (uint8_t*)malloc(131072);
    bool overflow = false;
    while (tmp && g_running) {
        ssize_t n = recv(sock, tmp, 131072, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            if (n < 0) LOG("socket: recv error (errno=%d) t=%llu.%03llu", errno, T_ARGS(now_us()));
            else LOG("socket: stream closed t=%llu.%03llu", T_ARGS(now_us()));
            break;
        }
        pthread_mutex_lock(&g_rbMutex);
        if ((size_t)n > kReaderBufBytes - g_rbFill) {
            overflow = true;
        } else {
            size_t tail = (g_rbHead + g_rbFill) % kReaderBufBytes;
            size_t first = kReaderBufBytes - tail < (size_t)n ? kReaderBufBytes - tail : (size_t)n;
            memcpy(g_rb + tail, tmp, first);
            memcpy(g_rb, tmp + first, (size_t)n - first);
            /* Find the asked-for keyframe: start code 00 00 01, NAL type 5. */
            for (ssize_t i = 0; g_rbJumpWanted && !g_rbJumpFound && i < n; ++i) {
                uint8_t b = tmp[i];
                if (g_rbScanHeader) {
                    g_rbScanHeader = false;
                    if ((b & 0x1f) == 5 && g_rbWritten + (uint64_t)i >= 3u) {
                        g_rbJumpAt = g_rbWritten + (uint64_t)i - 3u;
                        g_rbJumpFound = true;
                    }
                }
                if (b == 0) { ++g_rbScanZeros; continue; }
                if (b == 1 && g_rbScanZeros >= 2) g_rbScanHeader = true;
                g_rbScanZeros = 0;
            }
            g_rbWritten += (uint64_t)n;
            g_rbFill += (size_t)n;
            if (g_rbFill > g_rbHigh) g_rbHigh = g_rbFill;
            pthread_cond_signal(&g_rbCond);
        }
        pthread_mutex_unlock(&g_rbMutex);
        if (overflow) {
            LOG("socket: reader buffer full (%zu KB behind) t=%llu.%03llu",
                kReaderBufBytes / 1024u, T_ARGS(now_us()));
            break;
        }
    }
    free(tmp);
    pthread_mutex_lock(&g_rbMutex);
    g_rbClosed = true;
    pthread_cond_broadcast(&g_rbCond);
    pthread_mutex_unlock(&g_rbMutex);
    return NULL;
}

/* Decoder side: like recv(), 0 once the reader has finished and the buffer is
 * empty. *skipped is how much was dropped to reach an asked-for keyframe. */
static ssize_t reader_take(uint8_t* out, size_t max, size_t* backlog, size_t* skipped) {
    pthread_mutex_lock(&g_rbMutex);
    while (g_rbFill == 0 && !g_rbClosed && g_running) pthread_cond_wait(&g_rbCond, &g_rbMutex);
    *skipped = 0;
    if (g_rbJumpFound) {
        if (g_rbJumpAt > g_rbRead && g_rbJumpAt - g_rbRead < g_rbFill) {
            size_t drop = (size_t)(g_rbJumpAt - g_rbRead);
            /* Frames in the skipped bytes are never decoded: ACK them. */
            size_t dfirst = kReaderBufBytes - g_rbHead < drop ? kReaderBufBytes - g_rbHead : drop;
            ack_count_bytes(g_rb + g_rbHead, dfirst);
            ack_count_bytes(g_rb, drop - dfirst);
            g_rbHead = (g_rbHead + drop) % kReaderBufBytes;
            g_rbFill -= drop;
            g_rbRead += drop;
            *skipped = drop;
        }
        g_rbJumpFound = g_rbJumpWanted = false;
    }
    size_t n = g_rbFill < max ? g_rbFill : max;
    size_t first = kReaderBufBytes - g_rbHead < n ? kReaderBufBytes - g_rbHead : n;
    memcpy(out, g_rb + g_rbHead, first);
    memcpy(out + first, g_rb, n - first);
    g_rbHead = (g_rbHead + n) % kReaderBufBytes;
    g_rbFill -= n;
    g_rbRead += n;
    *backlog = g_rbFill;
    pthread_mutex_unlock(&g_rbMutex);
    return (ssize_t)n;
}

/* Ask harman-f's hook for a keyframe (its manual resync) and watch for it. */
static void ask_for_keyframe(size_t backlog) {
    int fd = open(kResyncArmMarker, O_CREAT | O_WRONLY, 0644);
    if (fd >= 0) close(fd);
    pthread_mutex_lock(&g_rbMutex);
    g_rbJumpWanted = true;
    g_rbJumpFound = false;
    g_rbScanZeros = 0;
    g_rbScanHeader = false;
    pthread_mutex_unlock(&g_rbMutex);
    if (g_rbJumps < 50)
        LOG("decoder: %zu KB behind, asked the phone for a keyframe t=%llu.%03llu",
            backlog / 1024u, T_ARGS(now_us()));
}

static void* DecoderThreadFunc(void* arg) {
    (void)arg;
    LOG("decoder: background worker thread active");

    bool is_socket = g_isSocket;
    bool is_unix = (strncmp(g_videoSource, "unix://", 7) == 0 ||
                    (strncmp(g_videoSource, "/tmp/", 5) == 0 && strstr(g_videoSource, ".sock") != NULL));
    char unix_path[512] = "/tmp/gal_video.sock";
    char host[512] = "127.0.0.1";
    int  port = 12346;

    if (is_unix) {
        if (strncmp(g_videoSource, "unix://", 7) == 0) {
            snprintf(unix_path, sizeof(unix_path), "%s", g_videoSource + 7);
        } else {
            snprintf(unix_path, sizeof(unix_path), "%s", g_videoSource);
        }
        LOG("network: target stream unix://%s", unix_path);
    } else if (g_isSocket) {
        const char* p = g_videoSource + 6;
        char* colon = (char*)strchr(p, ':');
        if (colon) {
            size_t host_len = colon - p;
            if (host_len >= sizeof(host)) host_len = sizeof(host) - 1;
            strncpy(host, p, host_len);
            host[host_len] = '\0';
            port = atoi(colon + 1);
        } else {
            snprintf(host, sizeof(host), "%s", p);
        }
        LOG("network: target stream tcp://%s:%d", host, port);
    } else {
        LOG("file: reading local H.264 file '%s' (loop=%d)", g_videoSource, g_loopFile ? 1 : 0);
    }

    const AVCodec* codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!codec) { LOGE("avcodec: H.264 decoder not found"); return NULL; }

    AVCodecParserContext* parser = av_parser_init(codec->id);
    if (!parser) { LOGE("avcodec: parser init failed"); return NULL; }

    AVCodecContext* codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx) { LOGE("avcodec: context alloc failed"); av_parser_close(parser); return NULL; }

    codecCtx->thread_count = g_ffmpegThreadCount;
    codecCtx->thread_type = g_ffmpegThreadType;
    if (g_ffmpegLowDelay) {
        codecCtx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    }
    if (g_ffmpegFastDecode) codecCtx->flags2 |= AV_CODEC_FLAG2_FAST;
    codecCtx->skip_frame = (AVDiscard)g_ffmpegSkipFrame;
    codecCtx->skip_loop_filter = (AVDiscard)g_ffmpegSkipLoopFilter;

    const char* deblock_name = "DEFAULT";
    if (g_ffmpegSkipLoopFilter == AVDISCARD_ALL) deblock_name = "ALL (Deblocking DISABLED, saves ~25-30% CPU)";
    else if (g_ffmpegSkipLoopFilter == AVDISCARD_NONE) deblock_name = "NONE (Deblocking ENABLED)";
    else if (g_ffmpegSkipLoopFilter == AVDISCARD_NONREF) deblock_name = "NONREF (Deblocking skipped on non-reference frames)";

    const char* thread_type_name = "FRAME (Multi-core parallel)";
    if (g_ffmpegThreadType == FF_THREAD_SLICE) thread_type_name = "SLICE (Single-slice fallback)";
    else if (g_ffmpegThreadType == (FF_THREAD_FRAME | FF_THREAD_SLICE)) thread_type_name = "FRAME+SLICE";

    LOG("decoder: configuring FFmpeg (threads: %d, type: %s, low_delay: %d, fast: %d, skip_loop_filter: %s, idle_bytes: %d, heartbeat: %dHz)",
        g_ffmpegThreadCount, thread_type_name, g_ffmpegLowDelay ? 1 : 0, g_ffmpegFastDecode ? 1 : 0, deblock_name,
        g_idleMaxBytes, g_idleHeartbeatHz);

    if (avcodec_open2(codecCtx, codec, NULL) < 0) {
        LOGE("avcodec: open failed");
        avcodec_free_context(&codecCtx);
        av_parser_close(parser);
        return NULL;
    }

    AVPacket* packet = av_packet_alloc();
    AVFrame*  frame  = av_frame_alloc();
    uint8_t* inbuf = (uint8_t*)av_malloc(262144 + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!inbuf) {
        LOGE("avcodec: inbuf allocation failed");
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecCtx);
        av_parser_close(parser);
        return NULL;
    }

    bool hasDecodedKeyframe = false;
    bool hasRenderedWarmupFrame = false;
    /* In this thread: the parser calls back on the thread that feeds it. */
    if (g_nvmWanted) nvm_open();
    bool gotData = false;
    bool behind = false;
    pthread_t readerThread;
    bool readerRunning = false;
    uint64_t nextReaderLogUs = 0;
    uint64_t nextKeyframeAskUs = 0;

    while (g_running) {
        int sock = -1;
        FILE* infile = NULL;

        if (is_socket) {
            if (is_unix) {
                sock = socket(AF_UNIX, SOCK_STREAM, 0);
                if (sock < 0) { usleep(100000); continue; }

                struct sockaddr_un serv_un;
                memset(&serv_un, 0, sizeof(serv_un));
                serv_un.sun_family = AF_UNIX;
                strncpy(serv_un.sun_path, unix_path, sizeof(serv_un.sun_path) - 1);

                g_streamSock = sock;
                int rcv_buf = 2097152; // 2MB socket receive buffer for large I-frames
                setsockopt(sock, SOL_SOCKET, SO_RCVBUF, (char*)&rcv_buf, sizeof(rcv_buf));

                LOG("socket: connecting to unix://%s...", unix_path);
                if (connect(sock, (struct sockaddr*)&serv_un, sizeof(serv_un)) < 0) {
                    g_streamSock = -1;
                    close(sock);
                    if (!connect_retry_allowed()) break;
                    continue;
                }
                LOG("socket: connected successfully to unix://%s!", unix_path);
                hasDecodedKeyframe = false;
                hasRenderedWarmupFrame = false;
            } else {
                sock = socket(AF_INET, SOCK_STREAM, 0);
                if (sock < 0) { usleep(100000); continue; }

                struct sockaddr_in serv_addr;
                memset(&serv_addr, 0, sizeof(serv_addr));
                serv_addr.sin_family = AF_INET;
                serv_addr.sin_port = htons(port);
                inet_pton(AF_INET, host, &serv_addr.sin_addr);

                g_streamSock = sock;
                int flag = 1;
                setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char*)&flag, sizeof(flag));

                int rcv_buf = 2097152; // 2MB socket receive buffer
                setsockopt(sock, SOL_SOCKET, SO_RCVBUF, (char*)&rcv_buf, sizeof(rcv_buf));

                LOG("socket: connecting to %s:%d...", host, port);
                if (connect(sock, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
                    g_streamSock = -1;
                    close(sock);
                    if (!connect_retry_allowed()) break;
                    continue;
                }
                LOG("socket: connected successfully to %s:%d!", host, port);
                hasDecodedKeyframe = false;
                hasRenderedWarmupFrame = false;
            }
        } else {
            infile = fopen(g_videoSource, "rb");
            if (!infile) {
                LOGE("file: failed to open '%s'", g_videoSource);
                break;
            }
        }

        if (is_socket && sock >= 0 && g_bufferedReader && !readerRunning) {
            if (!g_rb) g_rb = (uint8_t*)malloc(kReaderBufBytes);
            g_rbHead = g_rbFill = 0;
            g_rbClosed = false;
            g_rbWritten = g_rbRead = 0;
            g_rbJumpWanted = g_rbJumpFound = false;
            if (g_rb && pthread_create(&readerThread, NULL, ReaderThreadFunc, (void*)(intptr_t)sock) == 0) {
                readerRunning = true;
                int fd = open(kResyncEnableMarker, O_CREAT | O_WRONLY, 0644);
                if (fd >= 0) close(fd);
                LOG("socket: buffered reader on (%zu KB)", kReaderBufBytes / 1024u);
            } else {
                LOG("socket: buffered reader unavailable; reading directly");
            }
        }

        while (g_running) {
            ssize_t bytes_read = 0;
            if (g_ackEveryFrame && g_ackConsumed == 0 && g_decodedFrameCount >= 30) {
                /* No delimiters: the hook is not in this mode (an older hook,
                 * or the setting reached only the player). Counting nothing
                 * would never ACK and the hook would kill the player as hung. */
                g_ackEveryFrame = false;
                LOG("acks: no frame delimiters from the hook after %u pictures; ACKing drawn pictures only (GAL_ACK_EVERY_FRAME needs the hook's mode too)",
                    (unsigned)g_decodedFrameCount);
            }
            if (g_ackEveryFrame) {
                /* The previous buffer is decoded: ACK its frames, except
                 * the picture the render loop has not drawn yet. */
                pthread_mutex_lock(&g_frameMutex);
                bool waiting = g_framePool.readySlot >= 0;
                pthread_mutex_unlock(&g_frameMutex);
                ack_settle(waiting);
            }
            if (readerRunning) {
                size_t backlog = 0, skipped = 0;
                bytes_read = reader_take(inbuf, 131072, &backlog, &skipped);
                if (bytes_read == 0) break; /* the reader logged why */
                remember_param_sets(inbuf, (size_t)bytes_read);
                if (skipped > 0) {
                    /* Start clean at the keyframe: no half picture from before it. */
                    av_parser_close(parser);
                    parser = av_parser_init(codec->id);
                    if (!parser) { LOGE("avcodec: parser init failed"); g_running = false; break; }
                    avcodec_flush_buffers(codecCtx);
                    if (g_paramSetsLen > 0) {
                        uint8_t* unused = NULL;
                        int unusedSize = 0;
                        av_parser_parse2(parser, codecCtx, &unused, &unusedSize,
                                         g_paramSets, (int)g_paramSetsLen,
                                         AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
                    }
                    if (++g_rbJumps <= 50)
                        LOG("decoder: keyframe arrived; skipped %zu KB queued before it, the picture jumps to the present t=%llu.%03llu",
                            skipped / 1024u, T_ARGS(now_us()));
                }
                if (backlog > kReaderJumpOn && now_us() >= nextKeyframeAskUs) {
                    ask_for_keyframe(backlog);
                    nextKeyframeAskUs = now_us() + 3000000ULL;
                }
                if (!gotData) {
                    gotData = true;
                    LOG("socket: first data t=%llu.%03llu", T_ARGS(now_us()));
                }
                if (!behind && backlog > kReaderBehindOn) {
                    behind = true;
                    ++g_rbBehindEpisodes;
                    /* Only pictures nothing refers to lose their loop filter.
                     * Until v1.2.3 every picture did (AVDISCARD_ALL): the
                     * unfiltered blocks of a reference picture stay in all
                     * pictures predicted from it, so the map smeared until
                     * the next keyframe (#97). */
                    if (g_ffmpegSkipLoopFilter < AVDISCARD_NONREF)
                        codecCtx->skip_loop_filter = AVDISCARD_NONREF;
                    if (g_rbBehindEpisodes <= 20)
                        LOG("decoder: %zu KB behind t=%llu.%03llu",
                            backlog / 1024u, T_ARGS(now_us()));
                } else if (behind && backlog < kReaderBehindOff) {
                    behind = false;
                    codecCtx->skip_loop_filter = (AVDiscard)g_ffmpegSkipLoopFilter;
                    if (g_rbBehindEpisodes <= 20)
                        LOG("decoder: caught up t=%llu.%03llu", T_ARGS(now_us()));
                }
                uint64_t now = now_us();
                if (now >= nextReaderLogUs) {
                    if (nextReaderLogUs)
                        LOG("socket: reader backlog now %zu KB, most %zu KB, catch-ups %llu",
                            backlog / 1024u, g_rbHigh / 1024u, (unsigned long long)g_rbBehindEpisodes);
                    nextReaderLogUs = now + 30000000ULL;
                }
            } else if (is_socket) {
                primary_restart_check();
                bytes_read = recv(sock, inbuf, 131072, 0);
                if (bytes_read < 0) {
                    if (errno == EINTR) continue;
                    LOG("socket: recv error (errno=%d) t=%llu.%03llu", errno, T_ARGS(now_us()));
                    break;
                } else if (bytes_read == 0) {
                    LOG("socket: stream closed t=%llu.%03llu", T_ARGS(now_us()));
                    break;
                }
                if (!gotData) {
                    gotData = true;
                    LOG("socket: first data t=%llu.%03llu", T_ARGS(now_us()));
                }
            } else {
                bytes_read = fread(inbuf, 1, 32768, infile);
                if (bytes_read <= 0) {
                    if (g_loopFile && g_running) {
                        rewind(infile);
                        continue;
                    }
                    LOG("file: reached EOF");
                    break;
                }
            }

            uint8_t* data = inbuf;
            size_t data_size = bytes_read;

            while (data_size > 0 && g_running) {
                int len = av_parser_parse2(parser, codecCtx,
                                          &packet->data, &packet->size,
                                          data, data_size,
                                          AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
                if (len < 0) break;
                ack_count_bytes(data, (size_t)len);
                data += len;
                data_size -= len;

                if (packet->size > 0 && g_nvssActive) {
                    /* Hardware path: the parser's access units go to NvSS,
                     * which draws them on the layer itself. */
                    if (!hasDecodedKeyframe) {
                        if (!parser->key_frame) continue;
                        hasDecodedKeyframe = true;
                        LOG("decoder: first keyframe for the hardware decoder t=%llu.%03llu", T_ARGS(now_us()));
                    }
                    uint64_t t_dec_start = now_us();
                    if (nvss_decode(packet->data, packet->size) != 0) {
                        nvss_disable_for_boot(g_decodedFrameCount ? "decode failed" : "first decode failed");
                        g_running = false;
                        pthread_cond_broadcast(&g_frameCond);
                        break;
                    }
                    if (g_decodedFrameCount == 0) request_display_switch();
                    pthread_mutex_lock(&g_frameMutex);
                    g_decodedFrameCount++;
                    g_lastDecodeDurationUs = now_us() - t_dec_start;
                    g_newFrameReady = true;
                    pthread_cond_signal(&g_frameCond);
                    pthread_mutex_unlock(&g_frameMutex);
                    /* NvSS draws it itself: nothing waits in the pool. */
                    if (g_ackEveryFrame) ack_settle(false); else write_ack();
                    continue;
                }
                if (packet->size > 0 && g_nvmActive) {
                    /* Hardware path into memory: the unit's decoder fills
                     * the frame pool; drawing and pacing are the software
                     * path's. */
                    if (!hasDecodedKeyframe) {
                        if (!parser->key_frame) continue;
                        hasDecodedKeyframe = true;
                        LOG("decoder: first IDR/I keyframe received t=%llu.%03llu; warming up one frame.", T_ARGS(now_us()));
                        request_display_switch();
                    }
                    if (!nvm_decode(packet->data, packet->size, parser->key_frame == 1)) {
                        nvss_disable_for_boot("decode into memory failed");
                        g_running = false;
                        pthread_cond_broadcast(&g_frameCond);
                        break;
                    }
                    continue;
                }
                if (packet->size > 0) {
                    uint64_t t_dec_start = now_us();
                    int ret = avcodec_send_packet(codecCtx, packet);
                    if (ret < 0) continue;

                    while (ret >= 0 && g_running) {
                        ret = avcodec_receive_frame(codecCtx, frame);
                        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
                        if (ret < 0) break;

                        uint64_t dec_dur = now_us() - t_dec_start;

                        int w = frame->width;
                        int h = frame->height;

                        bool isKey = false;
#ifdef AV_FRAME_FLAG_KEY
                        if ((frame->flags & AV_FRAME_FLAG_KEY) != 0) isKey = true;
#endif
                        if (frame->key_frame != 0) isKey = true;
                        if (frame->pict_type == AV_PICTURE_TYPE_I) isKey = true;

                        // Keyframe Gate: Discard pre-keyframe P-frames to eliminate initial macroblock mosaic
                        if (!hasDecodedKeyframe) {
                            if (!isKey) {
                                av_frame_unref(frame);
                                continue;
                            }
                            hasDecodedKeyframe = true;
                            LOG("decoder: first IDR/I keyframe received (%dx%d) t=%llu.%03llu; warming up one frame.",
                                w, h, T_ARGS(now_us()));
                            request_display_switch();
                        }

                        /*
                         * The first decoded IDR establishes codec/reference
                         * state but can still contain stale macroblocks when
                         * a client joins in the middle of an AA session. Keep
                         * the pre-filled black frame visible for one decoded
                         * frame, then publish the next frame once the decoder
                         * has had a clean reference to work from.
                         */
                        if (!hasRenderedWarmupFrame) {
                            hasRenderedWarmupFrame = true;
                            av_frame_unref(frame);
                            LOG("decoder: warmup frame consumed; rendering next decoded frame.");
                            continue;
                        }

                        // Direct memcpy to contiguous YUV buffer
                        pthread_mutex_lock(&g_frameMutex);
                        RGBABuffer* buf = g_framePool.getWriteBuffer(w, h);
                        buf->packetBytes = packet->size;
                        buf->isKeyframe = isKey;
                        {
                            /* What the stream says about its colours (GAL_PLAYER_COLOR). */
                            bool spaceUnset = frame->colorspace == AVCOL_SPC_UNSPECIFIED ||
                                              frame->colorspace == AVCOL_SPC_RESERVED;
                            buf->colorFull = frame->color_range == AVCOL_RANGE_JPEG;
                            buf->colorBt709 = frame->colorspace == AVCOL_SPC_BT709 ||
                                              (spaceUnset && h >= 720);
                            static int s_lastRange = -1, s_lastSpace = -1, s_lastH = -1;
                            if ((int)frame->color_range != s_lastRange ||
                                (int)frame->colorspace != s_lastSpace || h != s_lastH) {
                                s_lastRange = (int)frame->color_range;
                                s_lastSpace = (int)frame->colorspace;
                                s_lastH = h;
                                LOG("colour: stream range %d, matrix %d (%dx%d); drawn as %s",
                                    s_lastRange, s_lastSpace, w, h,
                                    !g_colorAuto ? "full-range BT.601 (GAL_PLAYER_COLOR=old)" :
                                    buf->colorFull ? (buf->colorBt709 ? "full-range BT.709" : "full-range BT.601") :
                                                     (buf->colorBt709 ? "limited-range BT.709" : "limited-range BT.601"));
                            }
                        }
                        
                        uint8_t* dstY = buf->pixels;
                        uint8_t* dstU = dstY + (w * h);
                        uint8_t* dstV = dstU + ((w / 2) * (h / 2));

                        // Copy Y plane
                        for (int y = 0; y < h; ++y) {
                            memcpy(dstY + y * w, frame->data[0] + y * frame->linesize[0], w);
                        }
                        if ((g_decodedFrameCount & 31u) == 0) {
                            uint64_t sum = 0, count = 0;
                            for (int y = 8; y < h; y += 16)
                                for (int x = 8; x < w; x += 16, ++count) sum += dstY[y * w + x];
                            g_lastLuma = count ? (unsigned)(sum / count) : 0u;
                        }
                        // Copy U plane
                        for (int y = 0; y < h / 2; ++y) {
                            memcpy(dstU + y * (w / 2), frame->data[1] + y * frame->linesize[1], w / 2);
                        }
                        // Copy V plane
                        for (int y = 0; y < h / 2; ++y) {
                            memcpy(dstV + y * (w / 2), frame->data[2] + y * frame->linesize[2], w / 2);
                        }

                        g_framePool.publishWrite();
                        g_newFrameReady = true;
                        g_decodedFrameCount++;
                        g_lastDecodeDurationUs = dec_dur;

                        pthread_cond_signal(&g_frameCond);
                        pthread_mutex_unlock(&g_frameMutex);

                        av_frame_unref(frame);

                        // Monotonic 30.00 FPS Target Clock Pacing for file playback
                        if (!is_socket) {
                            static uint64_t s_nextTargetUs = 0;
                            const uint64_t kFrameIntervalUs = 33333ULL;
                            uint64_t now = now_us();
                            if (s_nextTargetUs == 0 || now > s_nextTargetUs + 100000ULL) {
                                s_nextTargetUs = now + kFrameIntervalUs;
                            } else {
                                if (now < s_nextTargetUs) {
                                    usleep((useconds_t)(s_nextTargetUs - now));
                                }
                                s_nextTargetUs += kFrameIntervalUs;
                            }
                        }
                    }
                }
            }
        }

        if (readerRunning) {
            /* Unblock the reader's recv() before joining it. */
            if (sock >= 0) shutdown(sock, SHUT_RDWR);
            pthread_cond_broadcast(&g_rbCond);
            pthread_join(readerThread, NULL);
            readerRunning = false;
            unlink(kResyncEnableMarker);
            LOG("socket: reader backlog most %zu KB, catch-ups %llu, jumps to a keyframe %llu",
                g_rbHigh / 1024u, (unsigned long long)g_rbBehindEpisodes,
                (unsigned long long)g_rbJumps);
        }
        if (sock >= 0) { g_streamSock = -1; close(sock); sock = -1; }
        if (infile) { fclose(infile); infile = NULL; }
        if (is_socket) {
            /*
             * No reconnect. The hook never closes a working player's stream:
             * a closed stream is gal exiting or replacing this player, and on
             * the car every one of them was (6 of 6 on 2026-09-16; the
             * reconnect attempt that followed always failed). Ending here is
             * also how the player notices gal is gone, without a watchdog
             * thread polling for it.
             */
            g_running = false;
            pthread_cond_broadcast(&g_frameCond);
            break;
        }
        if (!g_running) break;
        if (!g_loopFile) break;
    }

    av_free(inbuf);
    av_frame_free(&frame);
    av_packet_free(&packet);
    nvm_close();
    avcodec_free_context(&codecCtx);
    av_parser_close(parser);
    LOG("decoder: worker thread exited cleanly");
    return NULL;
}

static int check_and_acquire_instance_lock() {
    int fd = open("/tmp/stream-player.lock", O_CREAT | O_RDWR, 0666);
    if (fd < 0) return 0; // If /tmp is inaccessible, proceed without lock
    struct flock fl;
    for (int retry = 0; retry < 5; ++retry) {
        memset(&fl, 0, sizeof(fl));
        fl.l_type = F_WRLCK;
        fl.l_whence = SEEK_SET;
        if (fcntl(fd, F_SETLK, &fl) == 0) {
            return fd; // Acquired exclusive process lock
        }
        if (errno == ENOSYS || errno == EINVAL) {
            // Filesystem (e.g. QNX /dev/shmem) does not support POSIX advisory locks
            return fd;
        }
        usleep(20000); // 20ms retry in case previous instance is exiting
    }
    close(fd);
    return -1; // Another instance is actively running!
}

static void load_player_config() {
    const char* env_val = getenv("GAL_PLAYER_DEBLOCK");
    if (!env_val) env_val = getenv("GAL_DEBLOCK");
    if (!env_val) env_val = getenv("GAL_SKIP_LOOP_FILTER");

    char conf_val[64] = {0};

    if (!env_val) {
        static const char* candidate_paths[] = {
            "/fs/sdb0/gal_dualscreen.conf",
            "/fs/sda0/gal_dualscreen.conf",
            "/tmp/gal_dualscreen.conf",
            "/eso/lib/gal_dualscreen/gal_dualscreen.conf",
            "./gal_dualscreen.conf",
            NULL
        };
        for (int i = 0; candidate_paths[i]; ++i) {
            FILE* f = fopen(candidate_paths[i], "r");
            if (!f) continue;
            char line[256];
            while (fgets(line, sizeof(line), f)) {
                char* p = line;
                while (*p == ' ' || *p == '\t') p++;
                if (*p == '#' || *p == '\r' || *p == '\n' || *p == '\0') continue;
                if (strncmp(p, "GAL_PLAYER_DEBLOCK=", 19) == 0 ||
                    strncmp(p, "GAL_DEBLOCK=", 12) == 0 ||
                    strncmp(p, "GAL_SKIP_LOOP_FILTER=", 21) == 0) {
                    char* eq = strchr(p, '=');
                    if (eq) {
                        char* val = eq + 1;
                        while (*val == ' ' || *val == '\t') val++;
                        char* end = val + strlen(val) - 1;
                        while (end >= val && (*end == '\r' || *end == '\n' || *end == ' ' || *end == '\t')) {
                            *end = '\0';
                            end--;
                        }
                        strncpy(conf_val, val, sizeof(conf_val) - 1);
                        break;
                    }
                }
            }
            fclose(f);
            if (conf_val[0] != '\0') {
                env_val = conf_val;
                break;
            }
        }
    }

    if (env_val) {
        if (strcmp(env_val, "all") == 0 || strcmp(env_val, "0") == 0 ||
            strcasecmp(env_val, "false") == 0 || strcasecmp(env_val, "off") == 0) {
            g_ffmpegSkipLoopFilter = AVDISCARD_ALL;
        } else if (strcmp(env_val, "none") == 0 || strcmp(env_val, "1") == 0 ||
                   strcasecmp(env_val, "true") == 0 || strcasecmp(env_val, "on") == 0) {
            g_ffmpegSkipLoopFilter = AVDISCARD_NONE;
        } else if (strcmp(env_val, "noref") == 0) {
            g_ffmpegSkipLoopFilter = AVDISCARD_NONREF;
        }
    }

    // Parse candidate config files for additional performance settings
    static const char* conf_files[] = {
        "/fs/sdb0/gal_dualscreen.conf",
        "/fs/sda0/gal_dualscreen.conf",
        "/tmp/gal_dualscreen.conf",
        "/eso/lib/gal_dualscreen/gal_dualscreen.conf",
        "./gal_dualscreen.conf",
        NULL
    };
    for (int i = 0; conf_files[i]; ++i) {
        FILE* f = fopen(conf_files[i], "r");
        if (!f) continue;
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            char* p = line;
            while (*p == ' ' || *p == '	') p++;
            if (*p == '#' || *p == '\r' || *p == '\n' || *p == '\0') continue;
            char* eq = strchr(p, '=');
            if (!eq) continue;
            *eq = '\0';
            char* key = p;
            char* val = eq + 1;
            while (*val == ' ' || *val == '	') val++;
            char* end = val + strlen(val) - 1;
            while (end >= val && (*end == '\r' || *end == '\n' || *end == ' ' || *end == '	')) {
                *end = '\0';
                end--;
            }
            if (strcmp(key, "GAL_PLAYER_THREADS") == 0) {
                int t = atoi(val);
                if (t >= 1 && t <= 8) g_ffmpegThreadCount = t;
            } else if (strcmp(key, "GAL_PLAYER_IDLE_BYTES") == 0) {
                g_idleMaxBytes = atoi(val);
            } else if (strcmp(key, "GAL_PLAYER_HEARTBEAT_HZ") == 0) {
                g_idleHeartbeatHz = atoi(val);
            } else if (strcmp(key, "GAL_PLAYER_DECODER") == 0) {
                g_hwDecoder = strcmp(val, "hw") == 0;
            } else if (strcmp(key, "GAL_PLAYER_WINDOW") == 0) {
                int w = 0, h = 0;
                if (sscanf(val, "%dx%d", &w, &h) == 2 &&
                    w >= 320 && w <= 1920 && h >= 160 && h <= 1080) {
                    windowWidth = w;
                    windowHeight = h;
                }
            } else if (strcmp(key, "GAL_SECONDARY_WIDTH") == 0) {
                int w = atoi(val);
                if (w == 800 || w == 1280 || w == 1920) g_streamFrameWidth = w;
            } else if (strcmp(key, "GAL_SECONDARY_HEIGHT") == 0) {
                int h = atoi(val);
                if (h == 480 || h == 720 || h == 1080) g_streamFrameHeight = h;
            } else if (strcmp(key, "GAL_SECONDARY_MARGINS") == 0) {
                int w = 0, h = 0;
                bool hdFrame = g_streamFrameWidth > 800 ||
                               g_streamFrameHeight > 480;
                if (sscanf(val, "%dx%d", &w, &h) == 2 && w >= 0 && h >= 0 &&
                    (hdFrame ? (w <= 1600 && h <= 920) :
                               (w <= 400 && h <= 240))) {
                    g_marginW = hdFrame ? w : (w & ~1);
                    g_marginH = hdFrame ? h : (h & ~1);
                }
            } else if (strcmp(key, "GAL_CROP_TOP") == 0) {
                int v = atoi(val);
                if (v >= 0 && v <= 240) g_cropTop = v;
            } else if (strcmp(key, "GAL_CROP_BOTTOM") == 0) {
                int v = atoi(val);
                if (v >= 0 && v <= 240) g_cropBottom = v;
            } else if (strcmp(key, "GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4") == 0) {
                /* Wide enough for any window of 320..1920 by 160..1080. */
                int e4 = atoi(val);
                if (e4 >= 1000 && e4 <= 80000) g_pixelAspectE4 = e4;
            } else if (strcmp(key, "GAL_PLAYER_NVSS_OUTPUT") == 0) {
                int o = atoi(val);
                if (o == 0 || o == 1) g_nvssOutput = (unsigned)o;
            } else if (strcmp(key, "GAL_VC_CONTEXT") == 0) {
                int v = atoi(val);
                if (v > 0 && v < 1000) g_vcContext = (unsigned)v;
            } else if (strcmp(key, "GAL_VC_DISPLAY") == 0) {
                int v = atoi(val);
                if (v > 0 && v < 1000) g_vcDisplay = (unsigned)v;
            } else if (strcmp(key, "GAL_VC_DISPLAYABLE_ID") == 0) {
                int v = atoi(val);
                if (v > 0 && v < 1000) g_vcDisplayable = (unsigned)v;
            } else if (strcmp(key, "GAL_VC_RESTORE_DISPLAYABLE_ID") == 0) {
                int v = atoi(val);
                if (v > 0 && v < 1000) g_vcRestore = (unsigned)v;
            } else if (strcmp(key, "GAL_PLAYER_STATS") == 0) {
                /* 0 drops the once-a-second STATS line; everything else is still logged. */
                g_verbose = atoi(val) != 0;
            } else if (strcmp(key, "GAL_PLAYER_COLOR") == 0) {
                /* auto (default): as the stream says; old: full-range BT.601 as before. */
                if (strcmp(val, "old") == 0) g_colorAuto = false;
                else if (strcmp(val, "auto") == 0) g_colorAuto = true;
            } else if (strcmp(key, "GAL_PLAYER_NEON") == 0) {
                /* 0: decode without NEON; anything else: NEON where the CPU has it. */
                g_neonAllowed = atoi(val) != 0;
            } else if (strcmp(key, "GAL_ACK_EVERY_FRAME") == 0) {
                /* 1: ACK every frame; the hook reads the same key. */
                g_ackEveryFrame = atoi(val) == 1;
            } else if (strcmp(key, "GAL_PLAYER_HW_HD") == 0) {
                /* 1: the unit's decoder into memory for 720p/1080p frames too. */
                g_hwHd = atoi(val) == 1;
            } else if (strcmp(key, "GAL_PLAYER_REASSERT") == 0) {
                /* 1: switch the cockpit to the player again when the unit set it back. */
                g_reassert = atoi(val) == 1;
            } else if (strcmp(key, "GAL_PLAYER_PRIORITY") == 0) {
                int p = atoi(val);
                if (p >= 0 && p <= 20) g_priority = p;
            } else if (strcmp(key, "GAL_PLAYER_PRIORITY_CAP") == 0) {
                int p = atoi(val);
                if (p >= 0 && p <= 20) g_priorityCap = p;
            } else if (strcmp(key, "GAL_DEBUG_PRIMARY") == 0) {
                if (atoi(val) == 1) g_primaryWatch = true;
            } else if (strcmp(key, "GAL_PRIMARY_RESTART_PAUSE_MS") == 0) {
                if (atoi(val) > 0) g_primaryWatch = true;
            } else if (strcmp(key, "GAL_PLAYER_SELECT_AT_START") == 0) {
                g_selectAtStart = atoi(val) != 0;
            }
        }
        fclose(f);
        break; // Stop at first found config file
    }
    /*
     * gal passes the frame it asked the phone for; it wins over the file,
     * which may have been switched since gal started (full_frame.sh).
     */
    env_val = getenv("GAL_SECONDARY_WIDTH");
    if (env_val) {
        int w = atoi(env_val);
        if (w == 800 || w == 1280 || w == 1920) g_streamFrameWidth = w;
    }
    env_val = getenv("GAL_SECONDARY_HEIGHT");
    if (env_val) {
        int h = atoi(env_val);
        if (h == 480 || h == 720 || h == 1080) g_streamFrameHeight = h;
    }
    env_val = getenv("GAL_SECONDARY_MARGINS");
    if (env_val) {
        int w = 0, h = 0;
        bool hdFrame = g_streamFrameWidth > 800 || g_streamFrameHeight > 480;
        if (sscanf(env_val, "%dx%d", &w, &h) == 2 && w >= 0 && h >= 0 &&
            (hdFrame ? (w <= 1600 && h <= 920) :
                       (w <= 400 && h <= 240))) {
            g_marginW = hdFrame ? w : (w & ~1);
            g_marginH = hdFrame ? h : (h & ~1);
        }
    }
    if (!((g_streamFrameWidth == 800 && g_streamFrameHeight == 480) ||
          (g_streamFrameWidth == 1280 && g_streamFrameHeight == 720) ||
          (g_streamFrameWidth == 1920 && g_streamFrameHeight == 1080))) {
        LOG("config: invalid Android Auto frame %dx%d; using 800x480",
            g_streamFrameWidth, g_streamFrameHeight);
        g_streamFrameWidth = 800;
        g_streamFrameHeight = 480;
        if (g_marginW > 400 || g_marginH > 240) {
            g_marginW = 0;
            g_marginH = 0;
        }
    }
    if (g_streamFrameWidth == 800 && g_streamFrameHeight == 480) {
        g_marginW &= ~1;
        g_marginH &= ~1;
    }
    env_val = getenv("GAL_CROP_TOP");
    if (env_val) {
        int v = atoi(env_val);
        if (v >= 0 && v <= 240) g_cropTop = v;
    }
    env_val = getenv("GAL_CROP_BOTTOM");
    if (env_val) {
        int v = atoi(env_val);
        if (v >= 0 && v <= 240) g_cropBottom = v;
    }
    env_val = getenv("GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4");
    if (env_val) {
        int e4 = atoi(env_val);
        if (e4 >= 1000 && e4 <= 80000) g_pixelAspectE4 = e4;
    }
    build_dmdt_args();
    if (g_vcContext != 70u || g_vcDisplay != 4u || g_vcDisplayable != 3u || g_vcRestore != 33u)
        LOG("dmdt: cockpit context %u on display %u, player displayable %u, stock map %u (from the settings)",
            g_vcContext, g_vcDisplay, g_vcDisplayable, g_vcRestore);

    // Environment variables override config file
    const char* env_threads = getenv("GAL_PLAYER_THREADS");
    if (env_threads) {
        int t = atoi(env_threads);
        if (t >= 1 && t <= 8) g_ffmpegThreadCount = t;
    }
    const char* env_idle_bytes = getenv("GAL_PLAYER_IDLE_BYTES");
    if (env_idle_bytes) {
        g_idleMaxBytes = atoi(env_idle_bytes);
    }
    /* gal's environment (the hook loads the settings into it) wins, so the
     * player and the hook always agree on GAL_ACK_EVERY_FRAME. */
    const char* env_ack = getenv("GAL_ACK_EVERY_FRAME");
    if (env_ack) g_ackEveryFrame = strcmp(env_ack, "1") == 0;
    const char* env_hb = getenv("GAL_PLAYER_HEARTBEAT_HZ");
    if (env_hb) {
        g_idleHeartbeatHz = atoi(env_hb);
    }
}

// ---------------- Application Entry Point ----------------

#if defined(__QNX__) || defined(__linux__)
static int g_ack_fd = -1;
/* --no-ack: the stream does not come from the Android Auto hook (CarPlay),
 * so there is nobody to pace; never touch gal's ACK socket. */
static bool g_noAck = false;
/*
 * At startup, not at the first swap: the hook grants the phone's stream only
 * once this socket is connected, and before the stream there is nothing to
 * swap. (It used to connect on the swap of an idle "WAITING FOR SIGNAL"
 * frame drawn after 1 s, which is why it came 1.2-1.5 s after the spawn.)
 * A failed connect is retried on the next ACK.
 */
static void ack_connect() {
    if (g_ack_fd >= 0 || g_noAck) return;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/gal_ack.sock", sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        close(fd);
        return;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    g_ack_fd = fd;
    LOG("ack: connected t=%llu.%03llu", T_ARGS(now_us()));
}

static void write_ack() {
    ack_connect();
    if (g_ack_fd >= 0) {
        char b = 1;
        /* MSG_NOSIGNAL: once gal is gone a late ACK must fail, not raise
         * SIGPIPE and kill the player before it restores the Kombi map. */
        int n = send(g_ack_fd, &b, 1, MSG_NOSIGNAL);
        if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            close(g_ack_fd);
            g_ack_fd = -1;
        }
    }
}
#else
static void ack_connect() {}
static void write_ack() {}
#endif

/* GAL_ACK_EVERY_FRAME: ACK every consumed frame except a picture still
 * waiting in the pool to be drawn. Called by the decoder after each buffer
 * and by the render loop after each draw. */
static void ack_settle(bool pictureWaiting) {
    static uint64_t s_nextLogUs = 0, s_lastSent = 0;
    pthread_mutex_lock(&g_ackLock);
    uint64_t target = g_ackConsumed;
    if (pictureWaiting && target > 0) --target;
    unsigned n = 0;
    while (g_ackSent < target) { write_ack(); ++g_ackSent; ++n; }
    uint64_t now = now_us();
    if (s_nextLogUs == 0) s_nextLogUs = now + 60000000ULL;
    else if (now >= s_nextLogUs) {
        LOG("acks: %llu frames ACKed in the last minute, %llu in all (GAL_ACK_EVERY_FRAME)",
            (unsigned long long)(g_ackSent - s_lastSent), (unsigned long long)g_ackSent);
        s_lastSent = g_ackSent;
        s_nextLogUs = now + 60000000ULL;
    }
    pthread_mutex_unlock(&g_ackLock);
    (void)n;
}

/*
 * GAL_PLAYER_PRIORITY: raise the player to this priority, never lower it.
 * Set on the main thread before any other starts, so the decoder, FFmpeg's
 * and the display-switch threads inherit it. The player is spawned from gal
 * and otherwise runs at whatever priority that thread had (QNX's default is
 * 10). A little above 10 is the cautious step: a software decoder far above
 * gal and the interface could starve them. Idea from AMDFX60's fork; not
 * car-tested. 0 (the default) changes nothing.
 */
static void apply_player_priority() {
#ifdef __QNX__
    if (g_priority <= 0 && g_priorityCap <= 0) return;
    struct sched_param param;
    int policy = 0;
    if (pthread_getschedparam(pthread_self(), &policy, &param) != 0) {
        LOGE("priority: cannot read the current priority");
        return;
    }
    int was = param.sched_priority;
    /* GAL_PLAYER_PRIORITY_CAP: below gal's own threads (16 on the Skoda), so
     * the centre screen's decoder and the USB threads go first (#125). */
    if (g_priorityCap > 0) {
        if (was <= g_priorityCap) {
            LOG("priority: %d, already at or below GAL_PLAYER_PRIORITY_CAP=%d", was, g_priorityCap);
            return;
        }
        param.sched_priority = g_priorityCap;
        int rcCap = pthread_setschedparam(pthread_self(), policy, &param);
        if (rcCap != 0) LOGE("priority: %d -> %d failed (%d)", was, g_priorityCap, rcCap);
        else LOG("priority: %d -> %d (GAL_PLAYER_PRIORITY_CAP)", was, g_priorityCap);
        return;
    }
    if (was >= g_priority) {
        LOG("priority: %d, already at or above GAL_PLAYER_PRIORITY=%d", was, g_priority);
        return;
    }
    param.sched_priority = g_priority;
    int rc = pthread_setschedparam(pthread_self(), policy, &param);
    if (rc != 0) LOGE("priority: %d -> %d failed (%d)", was, g_priority, rc);
    else LOG("priority: %d -> %d (GAL_PLAYER_PRIORITY)", was, g_priority);
#endif
}

int main(int argc, char* argv[]) {
    g_parentPid = getppid();
    int lock_fd = check_and_acquire_instance_lock();
    if (lock_fd < 0) {
        LOG("stream-player: another instance is already running, exiting immediately to prevent duplicate renderers");
        return 0;
    }
    load_player_config();
    apply_player_priority();

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--no-ack") == 0) {
#if defined(__QNX__) || defined(__linux__)
            g_noAck = true;
            g_ackEveryFrame = false; /* CarPlay: no hook, no delimiters */
#endif
            g_bufferedReader = true;
        } else if (strncmp(argv[i], "--size=", 7) == 0) {
            /* Window size; overrides GAL_PLAYER_WINDOW. For testing. */
            int w = 0, h = 0;
            if (sscanf(argv[i] + 7, "%dx%d", &w, &h) == 2 &&
                w >= 320 && w <= 1920 && h >= 160 && h <= 1080) {
                windowWidth = w;
                windowHeight = h;
#ifdef __QNX__
                g_windowFromArgs = true;
#endif
            }
        } else if (strcmp(argv[i], "--loop") == 0) {
            g_loopFile = true;
        } else if (strcmp(argv[i], "--overlay") == 0 || strcmp(argv[i], "--no-overlay") == 0) {
            /* Retained as accepted no-op options; the on-video metrics HUD was removed. */
        } else if (strcmp(argv[i], "--no-deblock") == 0) {
            g_ffmpegSkipLoopFilter = AVDISCARD_ALL;
        } else if (strcmp(argv[i], "--deblock") == 0) {
            g_ffmpegSkipLoopFilter = AVDISCARD_NONE;
        } else if (strncmp(argv[i], "--skip-loop-filter=", 19) == 0) {
            const char* opt = argv[i] + 19;
            if (strcmp(opt, "all") == 0) g_ffmpegSkipLoopFilter = AVDISCARD_ALL;
            else if (strcmp(opt, "none") == 0) g_ffmpegSkipLoopFilter = AVDISCARD_NONE;
            else if (strcmp(opt, "noref") == 0) g_ffmpegSkipLoopFilter = AVDISCARD_NONREF;
        } else if (strncmp(argv[i], "--dot-px=", 9) == 0) {
            /* Backward-compatible no-op; the on-video metrics HUD was removed. */
        } else if (strncmp(argv[i], "--threads=", 10) == 0) {
            int t = atoi(argv[i] + 10);
            if (t >= 1 && t <= 8) g_ffmpegThreadCount = t;
        } else if (strncmp(argv[i], "--idle-bytes=", 13) == 0) {
            g_idleMaxBytes = atoi(argv[i] + 13);
        } else if (strncmp(argv[i], "--heartbeat-hz=", 15) == 0) {
            g_idleHeartbeatHz = atoi(argv[i] + 15);
#ifndef __QNX__
        } else if (strncmp(argv[i], "--dump-video=", 13) == 0) {
            snprintf(g_dumpVideoPath, sizeof(g_dumpVideoPath), "%s", argv[i] + 13);
        } else if (strncmp(argv[i], "--dump-frames=", 14) == 0) {
            g_dumpMaxFrames = atoi(argv[i] + 14);
#endif
        } else if (strncmp(argv[i], "--url=", 6) == 0) {
            snprintf(g_videoSource, sizeof(g_videoSource), "%s", argv[i] + 6);
        } else if (argv[i][0] != '-') {
            snprintf(g_videoSource, sizeof(g_videoSource), "%s", argv[i]);
        }
    }

    bool is_unix_sock = (strncmp(g_videoSource, "unix://", 7) == 0 ||
                         (strncmp(g_videoSource, "/tmp/", 5) == 0 && strstr(g_videoSource, ".sock") != NULL));
    g_isSocket = (strncmp(g_videoSource, "tcp://", 6) == 0 || is_unix_sock);
    LOG("stream-player starting (source: %s, loop: %d, pool: %d)",
        g_videoSource, g_loopFile ? 1 : 0, kBufferPoolSize);
#ifdef __QNX__
    /*
     * FFmpeg is built with its hand-written NEON routines (build_local.sh);
     * its C code is not compiled for NEON, so the switch below removes every
     * NEON instruction from the decoder. FFmpeg cannot ask QNX whether the
     * processor has NEON, so the system page is asked here.
     * The QNX kernel of these units stops a NEON access at a misaligned
     * address (SIGBUS; v1.2.2 crashed that way at every start). The routines
     * known to do that are left out of the build. Should another one be
     * found, the crash handler leaves kNoNeonMarker and every later start
     * until the next reboot decodes with FFmpeg's C routines.
     * GAL_PLAYER_NEON=0 switches NEON off for good.
     */
    {
        unsigned cpuFlags = SYSPAGE_ENTRY(cpuinfo)->flags;
        const char* off = NULL;
        if (!(cpuFlags & ARM_CPU_FLAG_NEON)) off = "the processor reports no NEON";
        else if (!g_neonAllowed) off = "GAL_PLAYER_NEON=0";
        else if (access(kNoNeonMarker, F_OK) == 0) off = "an earlier start since the last reboot crashed";
        if (off) {
            /* All of FFmpeg's run-time chosen assembly off, not only NEON, so
             * this is as close to the v1.2.3 decoder as this build gets. */
            av_force_cpu_flags(0);
            LOG("cpu: NEON off: %s (flags 0x%x); FFmpeg decodes with its C routines", off, cpuFlags);
        } else {
            LOG("cpu: NEON on (flags 0x%x); FFmpeg decodes with its NEON routines", cpuFlags);
        }
    }
#endif

    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);
    signal(SIGSEGV, crash_signal_handler);
    signal(SIGABRT, crash_signal_handler);
    signal(SIGBUS,  crash_signal_handler);
    signal(SIGILL,  crash_signal_handler);
    signal(SIGFPE,  crash_signal_handler);

    /*
     * Hardware decode: no EGL window or GL at all, NvSS owns displayable 3.
     * This thread only reports statistics and waits for the end of the
     * stream; the decoder thread decodes, switches the cluster and ACKs.
     */
#ifdef __QNX__
    check_map_window();
#endif
    /* The hardware decoder fills the window with the frame, so at 800x480 it
     * is used only when the two are the same size; a 720p or 1080p stream
     * (CLUSTERMAP_720P/1080P) keeps its margins and is placed 1:1. */
    const bool hwAsked = g_hwDecoder;
    bool hdStream = g_streamFrameWidth > 800 || g_streamFrameHeight > 480;
    if (g_hwDecoder && !hdStream &&
        (windowWidth != 800 || windowHeight != 480)) {
        LOG("hwdecode: the window is %dx%d, not Android Auto's 800x480; not drawing straight to the display",
            windowWidth, windowHeight);
        g_hwDecoder = false;
    }
    if (g_hwDecoder && nvss_open(
            g_streamFrameWidth, g_streamFrameHeight, windowWidth, windowHeight,
            hdStream ? g_marginW : 0, hdStream ? g_marginH : 0)) {
        ack_connect();
        pthread_t hwThread;
        if (pthread_create(&hwThread, NULL, DecoderThreadFunc, NULL) != 0) {
            LOGE("decoder: failed to create background thread");
            nvss_close();
            return 1;
        }
        uint64_t lastUs = now_us(), lastCount = 0;
        struct rusage lastUsage;
        getrusage(RUSAGE_SELF, &lastUsage);
        while (g_running) {
            pthread_mutex_lock(&g_frameMutex);
            struct timespec until;
            clock_gettime(CLOCK_REALTIME, &until);
            until.tv_sec += 1;
            while (g_running && !g_newFrameReady) {
                if (pthread_cond_timedwait(&g_frameCond, &g_frameMutex, &until) != 0) break;
            }
            g_newFrameReady = false;
            pthread_mutex_unlock(&g_frameMutex);
            uint64_t now = now_us();
            if (now - lastUs >= 1000000ULL) {
                uint64_t count = g_decodedFrameCount;
                struct rusage cur;
                getrusage(RUSAGE_SELF, &cur);
                uint64_t cpuUs = (cur.ru_utime.tv_sec - lastUsage.ru_utime.tv_sec) * 1000000ULL +
                                 (cur.ru_utime.tv_usec - lastUsage.ru_utime.tv_usec) +
                                 (cur.ru_stime.tv_sec - lastUsage.ru_stime.tv_sec) * 1000000ULL +
                                 (cur.ru_stime.tv_usec - lastUsage.ru_stime.tv_usec);
                if (g_verbose && count > 0) {
                    LOG_STATS("HW DEC: %5.1f fps (%4.1fms) | CPU: %5.1f%% | MEM: %5.1f MB",
                              (double)(count - lastCount) * 1000000.0 / (double)(now - lastUs),
                              us_to_ms(g_lastDecodeDurationUs), (double)cpuUs * 100.0 / (double)(now - lastUs),
                              get_process_memory_mb());
                }
                lastUs = now; lastCount = count; lastUsage = cur;
            }
        }
        execute_final_commands();
        g_running = false;
        int hs = g_streamSock;
        if (hs >= 0) shutdown(hs, SHUT_RDWR);
        LOG("shutting down: waiting for decoder thread");
        pthread_join(hwThread, NULL);
        nvss_close();
        LOG("stream-player terminated cleanly");
        return 0;
    }

    /* hw where NvSS cannot draw to the cockpit (it reports no size on VW,
     * Skoda and SEAT): the unit's decoder into memory, drawn as software is. */
    g_nvmWanted = hwAsked;
    if (g_nvmWanted && (g_streamFrameWidth > 800 || g_streamFrameHeight > 480) && !g_hwHd) {
        /* Only reached when NvSS could not draw to this cockpit (VW, Skoda, SEAT). */
        g_nvmWanted = false;
        LOG("hwdecode: %dx%d frame decoded in software; the unit's decoder into memory "
            "is used up to 800x480 (GAL_PLAYER_HW_HD=1 for HD frames too: it blacked "
            "out the centre screen on a Skoda, #145)", g_streamFrameWidth, g_streamFrameHeight);
    }

#ifdef __QNX__
    // Keep libdisplayinit.so resident for the entire application lifetime!
    g_displayInitHandle = dlopen("libdisplayinit.so", RTLD_LAZY);
    if (!g_displayInitHandle) {
        fprintf(stderr, "Error loading libdisplayinit.so: %s\n", dlerror());
        return 1;
    }

    void (*display_init)(int, int) = (void (*)(int, int))dlsym(g_displayInitHandle, "display_init");
    if (display_init) display_init(0, 0);

    eglDisplay = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay == EGL_NO_DISPLAY) {
        fprintf(stderr, "EGL: no display\n");
        return 1;
    }

    EGLint major = 0, minor = 0;
    if (!eglInitialize(eglDisplay, &major, &minor)) {
        fprintf(stderr, "EGL: eglInitialize failed (0x%x)\n", eglGetError());
        return 1;
    }

    EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 1, EGL_GREEN_SIZE, 1, EGL_BLUE_SIZE, 1, EGL_ALPHA_SIZE, 1,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    EGLConfig configs[5];
    EGLint num_configs = 0;
    EGLNativeWindowType windowEgl = 0;
    int kdWindow = 0;

    eglChooseConfig(eglDisplay, config_attribs, configs, 5, &num_configs);
    if (num_configs == 0) {
        fprintf(stderr, "EGL: no suitable config found\n");
        return 1;
    }

    void (*display_create_window)(EGLDisplay, EGLConfig, int, int, int, EGLNativeWindowType*, int*) =
        (void (*)(EGLDisplay, EGLConfig, int, int, int, EGLNativeWindowType*, int*))dlsym(g_displayInitHandle, "display_create_window");

    if (display_create_window) {
        // Displayable 3 = Center display on Virtual Cockpit
        display_create_window(eglDisplay, configs[0], windowWidth, windowHeight, 3, &windowEgl, &kdWindow);
        LOG("display: window created %dx%d (win=%p, kd=%d)", windowWidth, windowHeight, (void*)windowEgl, kdWindow);
    }

    eglSurface = eglCreateWindowSurface(eglDisplay, configs[0], windowEgl, 0);
    if (eglSurface == EGL_NO_SURFACE) {
        fprintf(stderr, "EGL: eglCreateWindowSurface failed (0x%x)\n", eglGetError());
        return 1;
    }

    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint context_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    eglContext = eglCreateContext(eglDisplay, configs[0], EGL_NO_CONTEXT, context_attribs);
    if (eglContext == EGL_NO_CONTEXT) {
        fprintf(stderr, "EGL: eglCreateContext failed (0x%x)\n", eglGetError());
        return 1;
    }

    if (!eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
        fprintf(stderr, "EGL: eglMakeCurrent failed (0x%x)\n", eglGetError());
        return 1;
    }
    // Non-blocking buffer swap (interval 0):
    // Prevents eglSwapBuffers() from hanging on lost hardware VSYNC when
    // the Virtual Cockpit display powers off during vehicle ignition OFF.
    eglSwapInterval(eglDisplay, 0);
#else
    if (!glfwInit()) {
        LOGE("GLFW: failed to initialize");
        return 1;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

    g_glfwWindow = glfwCreateWindow(windowWidth, windowHeight, "VW Virtual Cockpit - Unified GLES2 Player", NULL, NULL);
    if (!g_glfwWindow) {
        LOGE("GLFW: failed to create window");
        glfwTerminate();
        return 1;
    }
    glfwSetWindowCloseCallback(g_glfwWindow, [](GLFWwindow* w) {
        (void)w;
        g_running = false;
        pthread_cond_broadcast(&g_frameCond);
    });
    glfwMakeContextCurrent(g_glfwWindow);
    glfwSwapInterval(0); // Driven by our monotonic target clock
#endif

    InitGL();
    ack_connect();

    // Pre-fill slot 0 with a blank black frame (Y=16, U=128, V=128)
    RGBABuffer* initBuf = g_framePool.getWriteBuffer(windowWidth, windowHeight);
    memset(initBuf->pixels, 16, (size_t)windowWidth * windowHeight);
    memset(initBuf->pixels + (size_t)windowWidth * windowHeight, 128, ((size_t)windowWidth * windowHeight) / 2);
    g_framePool.publishWrite();

    pthread_attr_t decAttr;
    pthread_attr_init(&decAttr);
    pthread_attr_setstacksize(&decAttr, 1024 * 1024);

    pthread_t decThread;
    if (pthread_create(&decThread, &decAttr, DecoderThreadFunc, NULL) != 0) {
        LOGE("decoder: failed to create background thread");
        pthread_attr_destroy(&decAttr);
        return 1;
    }
    pthread_attr_destroy(&decAttr);

    int prevFbW = 0, prevFbH = 0;
    bool firstFrame = true;

    uint64_t lastFpsUs = now_us();
    uint64_t frameCount = 0;
    double renderFps = 0.0;
    double decodeFps = 0.0;
    uint64_t lastDecCount = 0;
    double renderLatencyMs = 0.0;

    struct rusage lastUsage;
    getrusage(RUSAGE_SELF, &lastUsage);
    uint64_t lastCpuSampleUs = now_us();
    double cpuPct = 0.0;
    double processMemMb = 0.0;

    while (g_running) {
        pthread_mutex_lock(&g_frameMutex);
        while (!g_newFrameReady && g_running) {
            /*
             * The decoder signals every frame, and shutdown broadcasts, so
             * this sleeps until there is something to draw. The timeout only
             * bounds a wakeup lost to the signal handler; nothing is drawn
             * without a frame (the cluster is not showing this window before
             * the first keyframe anyway).
             */
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += 1;
            pthread_cond_timedwait(&g_frameCond, &g_frameMutex, &ts);
        }
        if (!g_running) {
            pthread_mutex_unlock(&g_frameMutex);
            break;
        }
        g_newFrameReady = false;

        uint64_t frameStartUs = now_us();

        RGBABuffer* dispBuf = g_framePool.getDisplayBuffer();
        if (dispBuf && dispBuf->pixels) {
            static uint64_t s_lastRenderUs = 0;
            bool isIdle = (g_idleMaxBytes > 0 && dispBuf->packetBytes > 0 &&
                           dispBuf->packetBytes <= g_idleMaxBytes && !dispBuf->isKeyframe);
            uint64_t heartbeatIntervalUs = (g_idleHeartbeatHz > 0) ? (1000000ULL / (uint64_t)g_idleHeartbeatHz) : 0ULL;
            uint64_t timeSinceRenderUs = frameStartUs - s_lastRenderUs;

            // Idle render bypass: when stationary, only render on heartbeat keepalive (~333ms at 3Hz)
            if (isIdle && heartbeatIntervalUs > 0 && s_lastRenderUs > 0 && timeSinceRenderUs < heartbeatIntervalUs) {
                pthread_mutex_unlock(&g_frameMutex);
                continue; // Skip texture upload & swap; previous surface stays presented cleanly
            }
            s_lastRenderUs = frameStartUs;

            int w = dispBuf->width;
            int h = dispBuf->height;
            if (firstFrame || w != prevFbW || h != prevFbH) fit_frame(w, h);

            uint8_t* pY = dispBuf->pixels;
            uint8_t* pU = pY + (w * h);
            uint8_t* pV = pU + ((w / 2) * (h / 2));

            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, g_texY);
            if (g_streamFrameWidth > 800 || g_streamFrameHeight > 480) {
                static GLint lastLumaFilter = -1;
                GLint filter = g_lumaExact ? GL_NEAREST : GL_LINEAR;
                if (filter != lastLumaFilter) {
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
                    lastLumaFilter = filter;
                }
            }
            if (firstFrame || w != prevFbW || h != prevFbH) {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, w, h, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pY);
            } else {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_LUMINANCE, GL_UNSIGNED_BYTE, pY);
            }

            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_2D, g_texU);
            if (firstFrame || w != prevFbW || h != prevFbH) {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, w/2, h/2, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pU);
            } else {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_LUMINANCE, GL_UNSIGNED_BYTE, pU);
            }

            glActiveTexture(GL_TEXTURE2);
            glBindTexture(GL_TEXTURE_2D, g_texV);
            if (firstFrame || w != prevFbW || h != prevFbH) {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, w/2, h/2, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pV);
                

                
                prevFbW = w;
                prevFbH = h;
                if (firstFrame)
                    LOG("render: first frame drawn t=%llu.%03llu", T_ARGS(now_us()));
                firstFrame = false;
            } else {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_LUMINANCE, GL_UNSIGNED_BYTE, pV);
            }
            
            pthread_mutex_unlock(&g_frameMutex);

            // Render to screen (GPU YUV Shader)
            glViewport(0, 0, windowWidth, windowHeight);
            glClear(GL_COLOR_BUFFER_BIT);

            if (g_useShader) {
                glUseProgram(g_programObject);
                glUniform1i(g_texLocY, 0);
                glUniform1i(g_texLocU, 1);
                glUniform1i(g_texLocV, 2);
                {
                    bool colorFull = !g_colorAuto || dispBuf->colorFull;
                    bool colorBt709 = g_colorAuto && dispBuf->colorBt709;
                    if (colorFull)
                        glUniform3f(g_rangeLoc, 0.0f, 1.0f, 1.0f);
                    else /* limited: Y 16-235 and Cb/Cr 16-240 stretched to 0-255 */
                        glUniform3f(g_rangeLoc, 16.0f / 255.0f, 255.0f / 219.0f, 255.0f / 224.0f);
                    if (colorBt709)
                        glUniform4f(g_matrixLoc, 1.5748f, 0.18732f, 0.46812f, 1.8556f);
                    else
                        glUniform4f(g_matrixLoc, 1.402f, 0.34414f, 0.71414f, 1.772f);
                }

                glVertexAttribPointer(g_posAttr, 3, GL_FLOAT, GL_FALSE, 0, fittedVertices);
                glVertexAttribPointer(g_texAttr, 2, GL_FLOAT, GL_FALSE, 0, croppedTexCoords);
                glEnableVertexAttribArray(g_posAttr);
                glEnableVertexAttribArray(g_texAttr);

                glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

                glDisableVertexAttribArray(g_posAttr);
                glDisableVertexAttribArray(g_texAttr);
            } else {
                static int s_noDrawWarn = 0;
                if (s_noDrawWarn++ < 3)
                    LOGE("render: SHADER PATH FAILED -- GPU YUV requires shaders! (Screen is blank)");
            }

#ifdef __QNX__
            if (!eglSwapBuffers(eglDisplay, eglSurface)) {
                EGLint err = eglGetError();
                if (err == EGL_CONTEXT_LOST) {
                    LOGE("render: EGL_CONTEXT_LOST (display power down or surface invalidated)");
                }
            }
            if (g_ackEveryFrame) {
                pthread_mutex_lock(&g_frameMutex);
                bool waiting = g_framePool.readySlot >= 0;
                pthread_mutex_unlock(&g_frameMutex);
                ack_settle(waiting);
            } else {
                write_ack();
            }
#else
            if (!g_dumpVideoPipe) {
                const char* dumpPath = getenv("GAL_PLAYER_DUMP_VIDEO");
                if ((!dumpPath || strlen(dumpPath) == 0) && g_dumpVideoPath[0] != '\0') {
                    dumpPath = g_dumpVideoPath;
                }
                const char* dumpFramesEnv = getenv("GAL_PLAYER_DUMP_FRAMES");
                if (dumpFramesEnv && g_dumpMaxFrames == 0) {
                    g_dumpMaxFrames = atoi(dumpFramesEnv);
                }
                if (dumpPath && strlen(dumpPath) > 0) {
                    char cmd[1024];
                    snprintf(cmd, sizeof(cmd),
                             "ffmpeg -y -f rawvideo -vcodec rawvideo -pix_fmt rgba -s %dx%d -r 30 -i - -vf vflip -c:v libx264 -pix_fmt yuv420p -preset fast \"%s\" >/dev/null 2>&1",
                             windowWidth, windowHeight, dumpPath);
                    g_dumpVideoPipe = popen(cmd, "w");
                    if (g_dumpVideoPipe) {
                        LOG("video dump: recording to %s (%dx%d @ 30 FPS, target_frames: %d)", dumpPath, windowWidth, windowHeight, g_dumpMaxFrames);
                    } else {
                        LOGE("video dump: failed to open ffmpeg pipe for %s", dumpPath);
                    }
                }
            }
            if (g_dumpVideoPipe) {
                static uint8_t* s_dumpBuf = NULL;
                if (!s_dumpBuf) {
                    s_dumpBuf = (uint8_t*)malloc((size_t)windowWidth * windowHeight * 4);
                }
                glReadPixels(0, 0, windowWidth, windowHeight, GL_RGBA, GL_UNSIGNED_BYTE, s_dumpBuf);
                fwrite(s_dumpBuf, 1, (size_t)windowWidth * windowHeight * 4, g_dumpVideoPipe);
                g_dumpFrameCount++;
                if (g_dumpMaxFrames > 0 && g_dumpFrameCount >= g_dumpMaxFrames) {
                    LOG("video dump: reached target %d frames, terminating", g_dumpFrameCount);
                    g_running = false;
                }
            }
            glfwSwapBuffers(g_glfwWindow);
            glfwPollEvents();
            if (g_ackEveryFrame) {
                pthread_mutex_lock(&g_frameMutex);
                bool waiting = g_framePool.readySlot >= 0;
                pthread_mutex_unlock(&g_frameMutex);
                ack_settle(waiting);
            } else {
                write_ack();
            }
#endif
        } else {
            pthread_mutex_unlock(&g_frameMutex);
        }

        frameCount++;
        uint64_t frameEndUs = now_us();
        renderLatencyMs = us_to_ms(frameEndUs - frameStartUs);

        if ((frameEndUs - lastFpsUs) >= 1000000ULL) {
            uint64_t elapsedUs = frameEndUs - lastFpsUs;
            renderFps = (double)frameCount * 1000000.0 / (double)elapsedUs;

            uint64_t curDec = g_decodedFrameCount;
            decodeFps = (double)(curDec - lastDecCount) * 1000000.0 / (double)elapsedUs;
            lastDecCount = curDec;

            /* Once a minute, always: is the picture still coming, and is it black? (#4) */
            static uint64_t s_healthUs = 0, s_healthDec = 0;
            if (s_healthUs == 0) {
                s_healthUs = frameEndUs;
                s_healthDec = curDec;
            } else if (frameEndUs - s_healthUs >= 60000000ULL) {
                char ctxNote[64] = "";
                int ctxShown = g_ctxShown;
                if (ctxShown >= 0) snprintf(ctxNote, sizeof(ctxNote), "; cockpit context shows window %d", ctxShown);
                else if (ctxShown == -2) snprintf(ctxNote, sizeof(ctxNote), "; cockpit context not listed");
                LOG("health: %llu pictures decoded in the last minute; brightness %u of 255 (under 16 is black)%s t=%llu.%03llu",
                    (unsigned long long)(curDec - s_healthDec), g_lastLuma, ctxNote, T_ARGS(frameEndUs));
                s_healthUs = frameEndUs;
                s_healthDec = curDec;
            }
            context_check_tick(frameEndUs);
            frameCount = 0;
            lastFpsUs = frameEndUs;

            struct rusage curUsage;
            getrusage(RUSAGE_SELF, &curUsage);
            uint64_t userUs = (curUsage.ru_utime.tv_sec - lastUsage.ru_utime.tv_sec) * 1000000ULL +
                              (curUsage.ru_utime.tv_usec - lastUsage.ru_utime.tv_usec);
            uint64_t sysUs  = (curUsage.ru_stime.tv_sec - lastUsage.ru_stime.tv_sec) * 1000000ULL +
                              (curUsage.ru_stime.tv_usec - lastUsage.ru_stime.tv_usec);
            uint64_t cpuElapsedUs = frameEndUs - lastCpuSampleUs;
            if (cpuElapsedUs > 0) {
                cpuPct = (double)(userUs + sysUs) * 100.0 / (double)cpuElapsedUs;
            }
            lastUsage = curUsage;
            lastCpuSampleUs = frameEndUs;

            processMemMb = get_process_memory_mb();

            if (g_verbose) {
                LOG_STATS("DISP: %5.1f fps | DEC: %5.1f fps (%4.1fms) | LAT: %4.1fms | CPU: %5.1f%% | MEM: %5.1f MB",
                          renderFps, decodeFps, us_to_ms(g_lastDecodeDurationUs),
                          renderLatencyMs, cpuPct, processMemMb);
            }
        }
    }

    // Put the stock Kombi map back (if this player switched it) before anything else.
    execute_final_commands();

    // Ensure decoder thread is unblocked from recv()
    g_running = false;
    int s = g_streamSock;
    if (s >= 0) {
        shutdown(s, SHUT_RDWR);
    }

#ifndef __QNX__
    if (g_dumpVideoPipe) {
        pclose(g_dumpVideoPipe);
        g_dumpVideoPipe = NULL;
    }
#endif
    LOG("shutting down: waiting for decoder thread");
    pthread_join(decThread, NULL);

#ifdef __QNX__
    if (eglDisplay != EGL_NO_DISPLAY) {
        eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (eglSurface != EGL_NO_SURFACE) eglDestroySurface(eglDisplay, eglSurface);
        if (eglContext != EGL_NO_CONTEXT) eglDestroyContext(eglDisplay, eglContext);
        eglTerminate(eglDisplay);
    }
    if (g_displayInitHandle) {
        // Do not call display_deinit() on exit: Tegra driver deadlocks on semaphore fc522a2c
        // while the display pipeline is active. The OS reclaims resources automatically.
        dlclose(g_displayInitHandle);
    }
#else
    if (g_glfwWindow) {
        glfwDestroyWindow(g_glfwWindow);
        glfwTerminate();
    }
#endif

    LOG("stream-player terminated cleanly");
    return 0;
}
