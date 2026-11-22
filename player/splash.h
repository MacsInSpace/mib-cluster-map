/*
 * Start-up splash: the project's mark between the car's map and the phone's.
 *
 * When the cockpit switches to this player (the phone's first keyframe), the
 * window shows the orbit spinner, "MacsInSpace/Mib-Cluster-Map" and "Free"
 * on black for SPLASH_HOLD_US, with the green dot turning, then fades into
 * the video over SPLASH_FADE_US. Decoding and ACKs carry on underneath, so
 * the phone sees no difference. It is drawn after the video in the same
 * frame: OpenGL paths only (software decode, and the unit's decoder into
 * memory on VW, Skoda and SEAT). NvSS (Audi hardware decode) draws straight
 * to the cockpit layer and gets no splash. CLUSTERMAP_SPLASH=0 turns it off.
 *
 * Artwork: player/splash/splash.svg, the owner's orbit spinner, rendered
 * into splash_art.h by tools/make_splash_art.py.
 */
#include "splash_art.h"

static bool g_splashOn = true;            /* CLUSTERMAP_SPLASH, 0 = off */
static bool g_splashDone = false;
static uint64_t g_splashStartUs = 0;
static GLuint g_splashProg = 0, g_splashArtTex = 0, g_splashDotTex = 0, g_splashBlankTex = 0;
static GLint g_splashPos = -1, g_splashUv = -1, g_splashTexLoc = -1, g_splashTintLoc = -1;

#define SPLASH_HOLD_US 1500000ULL
#define SPLASH_FADE_US 400000ULL
#define SPLASH_TURN_US 1500000.0          /* one turn of the dot, as in the SVG */
#define SPLASH_DOT_TEX 32

static const char* kSplashVs =
    "attribute vec2 p; attribute vec2 uv; varying vec2 v;\n"
    "void main() { v = uv; gl_Position = vec4(p, 0.0, 1.0); }\n";
static const char* kSplashFs =
    "precision mediump float; varying vec2 v; uniform sampler2D t; uniform vec4 tint;\n"
    "void main() { gl_FragColor = texture2D(t, v) * tint; }\n";

static bool splash_active() { return g_splashOn && !g_splashDone; }

static GLuint splash_texture(int w, int h, const unsigned char* px) {
    GLuint t = 0;
    glGenTextures(1, &t);
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glActiveTexture(GL_TEXTURE0);
    return t;
}

/* After InitGL. Any failure just turns the splash off. */
static void splash_init() {
    if (!g_splashOn) { LOG("splash: off (CLUSTERMAP_SPLASH=0)"); return; }
    GLuint vs = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vs, 1, &kSplashVs, NULL);
    glCompileShader(vs);
    check_shader(vs, "vert-splash");
    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fs, 1, &kSplashFs, NULL);
    glCompileShader(fs);
    check_shader(fs, "frag-splash");
    g_splashProg = glCreateProgram();
    glAttachShader(g_splashProg, vs);
    glAttachShader(g_splashProg, fs);
    glLinkProgram(g_splashProg);
    check_program(g_splashProg, "splash");
    GLint linked = 0;
    glGetProgramiv(g_splashProg, GL_LINK_STATUS, &linked);
    g_splashPos = glGetAttribLocation(g_splashProg, "p");
    g_splashUv = glGetAttribLocation(g_splashProg, "uv");
    g_splashTexLoc = glGetUniformLocation(g_splashProg, "t");
    g_splashTintLoc = glGetUniformLocation(g_splashProg, "tint");
    if (!linked || g_splashPos < 0 || g_splashUv < 0) {
        LOGE("splash: shader not usable; no splash");
        g_splashOn = false;
        return;
    }
    /* The dot: #5DCAA5, edge smoothed over one texel. */
    static unsigned char dot[SPLASH_DOT_TEX * SPLASH_DOT_TEX * 4];
    for (int y = 0; y < SPLASH_DOT_TEX; ++y) {
        for (int x = 0; x < SPLASH_DOT_TEX; ++x) {
            float dx = x + 0.5f - SPLASH_DOT_TEX / 2.0f, dy = y + 0.5f - SPLASH_DOT_TEX / 2.0f;
            float a = SPLASH_DOT_TEX / 2.0f - 1.0f - sqrtf(dx * dx + dy * dy) + 0.5f;
            a = a < 0.0f ? 0.0f : a > 1.0f ? 1.0f : a;
            unsigned char* p = dot + (y * SPLASH_DOT_TEX + x) * 4;
            p[0] = 0x5D; p[1] = 0xCA; p[2] = 0xA5; p[3] = (unsigned char)(a * 255.0f + 0.5f);
        }
    }
    static const unsigned char blank[4] = { 255, 255, 255, 255 };
    g_splashArtTex = splash_texture(SPLASH_W, SPLASH_H, kSplashArt);
    g_splashDotTex = splash_texture(SPLASH_DOT_TEX, SPLASH_DOT_TEX, dot);
    g_splashBlankTex = splash_texture(1, 1, blank);
    LOG("splash: ready (%dx%d art, %llu ms then a %llu ms fade)", SPLASH_W, SPLASH_H,
        (unsigned long long)(SPLASH_HOLD_US / 1000), (unsigned long long)(SPLASH_FADE_US / 1000));
}

/* One textured rectangle, in window pixels from the top left. */
static void splash_quad(float x0, float y0, float x1, float y1, int winW, int winH,
                        GLuint tex, float r, float g, float b, float a) {
    float l = x0 / winW * 2.0f - 1.0f, rt = x1 / winW * 2.0f - 1.0f;
    float t = 1.0f - y0 / winH * 2.0f, bt = 1.0f - y1 / winH * 2.0f;
    const GLfloat pos[8] = { l, t,  rt, t,  rt, bt,  l, bt };
    static const GLfloat uv[8] = { 0, 0,  1, 0,  1, 1,  0, 1 };
    glBindTexture(GL_TEXTURE_2D, tex);
    glUniform4f(g_splashTintLoc, r, g, b, a);
    glVertexAttribPointer(g_splashPos, 2, GL_FLOAT, GL_FALSE, 0, pos);
    glVertexAttribPointer(g_splashUv, 2, GL_FLOAT, GL_FALSE, 0, uv);
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
}

/* Render loop, after the video and before the swap. The first call starts it. */
static void splash_draw(int winW, int winH, uint64_t nowUs) {
    if (!splash_active()) return;
    if (g_splashStartUs == 0) { g_splashStartUs = nowUs; LOG("splash: shown"); }
    uint64_t el = nowUs - g_splashStartUs;
    if (el >= SPLASH_HOLD_US + SPLASH_FADE_US) {
        g_splashDone = true;
        LOG("splash: done, the phone's map is up");
        return;
    }
    float a = el < SPLASH_HOLD_US ? 1.0f
            : 1.0f - (float)(el - SPLASH_HOLD_US) / (float)SPLASH_FADE_US;
    float scale = 1.0f;
    if (scale > 0.8f * winW / SPLASH_W) scale = 0.8f * winW / SPLASH_W;
    if (scale > 0.8f * winH / SPLASH_H) scale = 0.8f * winH / SPLASH_H;
    float dw = SPLASH_W * scale, dh = SPLASH_H * scale;
    float x0 = (winW - dw) / 2.0f, y0 = (winH - dh) / 2.0f;
    float ang = (float)(el / SPLASH_TURN_US) * 6.2831853f;
    float cx = x0 + (SPLASH_CX + SPLASH_ORBIT * sinf(ang)) * scale;
    float cy = y0 + (SPLASH_CY - SPLASH_ORBIT * cosf(ang)) * scale;
    float r = SPLASH_DOT * scale;

    glUseProgram(g_splashProg);
    glActiveTexture(GL_TEXTURE3);
    glUniform1i(g_splashTexLoc, 3);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnableVertexAttribArray(g_splashPos);
    glEnableVertexAttribArray(g_splashUv);
    splash_quad(0, 0, (float)winW, (float)winH, winW, winH, g_splashBlankTex, 0, 0, 0, a);
    splash_quad(x0, y0, x0 + dw, y0 + dh, winW, winH, g_splashArtTex, 1, 1, 1, a);
    splash_quad(cx - r, cy - r, cx + r, cy + r, winW, winH, g_splashDotTex, 1, 1, 1, a);
    glDisableVertexAttribArray(g_splashPos);
    glDisableVertexAttribArray(g_splashUv);
    glDisable(GL_BLEND);
    glActiveTexture(GL_TEXTURE0);
}
