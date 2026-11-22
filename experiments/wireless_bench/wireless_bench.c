/*
 * Wireless Android Auto, bench test: gal running a phone session over the
 * car's Wi-Fi instead of USB. Test builds only (./build_local.sh
 * wireless-bench); gal_hook.c includes this file only with -DWIRELESS_BENCH,
 * so release builds do not contain it. README.md beside it has the steps.
 *
 * What it proves: that gal's Android Auto stack runs unchanged over a TCP
 * connection on the hotspot. The phone end is a relay on a laptop
 * (aa_usb_relay.py): the phone on the laptop's USB, the laptop on the car's
 * hotspot. The Bluetooth start that a phone needs to go wireless by itself
 * is the next step, and not here.
 *
 * How (all found in the P4521 gal, MHI2_ER_VWG13_P4521, 1269211 bytes):
 *   - gal's Transport (Google's receiver library) is an abstract stream:
 *     vtable +8 stopTransport, +0xc abstractRead, +0x10 abstractWrite;
 *     a read or write returns the bytes moved, -1 for "failed", -2 for "try
 *     again". gal::CUsbdiTransport is the only one in the stock build.
 *   - A session starts in CGALReceiver::processConnectGAL(this, busno,
 *     devno, const util::UnicodeString8 &usbPath, bool exlap), which
 *     smartphone_integrator's "device available" job calls. Its worker
 *     makes a CUsbdiTransport and calls CUsbdiTransport::init(this, busno,
 *     devno, usbPath) before starting it.
 *   - So: a listener on the hotspot accepts the relay, and calls
 *     processConnectGAL with a bus and device number no USB device has
 *     (250/250). The patched init sees those numbers, takes the socket and
 *     returns success without USB. The transport's read, write and stop go
 *     to the socket for that one object, and to the stock code for any
 *     other (a phone on the cable works as before).
 *   - The receiver's address comes from its job handler (vtable +0x28),
 *     which gal calls for every job from start-up on.
 *
 * Patched: four vtable slots of CUsbdiTransport and one of CGALReceiver
 * (gal's writable data), and the first two instructions of
 * CUsbdiTransport::init (a jump; the copy keeps the stock code reachable).
 * Every address and instruction word is checked before anything is
 * written, and on any mismatch nothing is patched. Off unless
 * GAL_WIRELESS_BENCH=1. Log: /tmp/wireless_bench.log.
 */
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define WB_LOG_PATH "/tmp/wireless_bench.log"
#define WB_PORT_DEFAULT 5288
#define WB_BUS 250u   /* no USB bus or device has these numbers */
#define WB_DEV 250u

typedef struct wb_layout {
    const char *name;
    uint32_t file_size;            /* /proc/self/exefile, the gal this is for */
    uint32_t usb_vtable;           /* _ZTVN3gal15CUsbdiTransportE (exported) */
    uint32_t recv_vtable;          /* _ZTVN3gal12CGALReceiverE (exported) */
    uint32_t usb_dtor, usb_dtor_del, usb_stop, usb_read, usb_write; /* slots 0, 4, 8, 0xc, 0x10 */
    uint32_t recv_job;             /* CGALReceiver job handler, vtable slot 0x28 */
    uint32_t init;                 /* CUsbdiTransport::init */
    uint32_t init_w0, init_w1;     /* push {r4-fp, lr}; ldr r4, [pc, #0x430] */
    uint32_t connect;              /* CGALReceiver::processConnectGAL */
    uint32_t connect_w0, connect_w1;
} wb_layout;

static const wb_layout k_layouts[] = {
    { "MHI2_ER_VWG13_P4521", 1269211u, 0x2321a0u, 0x231678u,
      0x1f7ab0u, 0x1f7e18u, 0x1f5470u, 0x1f6880u, 0x1f5d70u,
      0x1cb49cu,
      0x1f60c4u, 0xe92d4ff0u, 0xe59f4430u,
      0x1c9d64u, 0xe92d4ff0u, 0xe59f4494u },
};

typedef void (*wb_obj_fn)(void *self);
typedef int (*wb_io_fn)(void *self, void *buf, unsigned len);
typedef int (*wb_init_fn)(void *self, unsigned bus, unsigned dev, void *path);
typedef void (*wb_job_fn)(void *self, void *a, void *b, void *c);
typedef int (*wb_connect_fn)(void *self, unsigned bus, unsigned dev, void *path, unsigned exlap);
typedef void (*wb_ustr_fn)(void *self);

static const wb_layout *g_wb;
static int g_wb_log = -1;
static pthread_mutex_t g_wb_lock = PTHREAD_MUTEX_INITIALIZER;
static wb_obj_fn g_usb_dtor, g_usb_dtor_del, g_usb_stop;
static wb_io_fn g_usb_read, g_usb_write;
static wb_job_fn g_recv_job;
static wb_init_fn g_init_tramp;
static wb_connect_fn g_connect;
static wb_ustr_fn g_ustr_ctor, g_ustr_dtor;
static void *volatile g_recv;      /* the CGALReceiver */
static void *volatile g_tr;        /* the transport that is ours */
static volatile int g_fd = -1;     /* its socket */
static volatile int g_pending = -1; /* accepted, waiting for init */
static volatile unsigned long g_rx, g_tx;

static void wb_logf(const char *fmt, ...)
{
    char line[512];
    struct timespec ts;
    va_list ap;
    int n, m;

    if (g_wb_log < 0) return;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    n = snprintf(line, sizeof(line), "%ld.%03ld ", (long)ts.tv_sec, ts.tv_nsec / 1000000L);
    if (n < 0) n = 0;
    va_start(ap, fmt);
    m = vsnprintf(line + n, sizeof(line) - (size_t)n - 1, fmt, ap);
    va_end(ap);
    if (m < 0) m = 0;
    n += m;
    if (n > (int)sizeof(line) - 2) n = (int)sizeof(line) - 2;
    line[n++] = '\n';
    (void)write(g_wb_log, line, (size_t)n);
}

/* ---- the transport, for our object only ------------------------------- */

static int wb_read(void *self, void *buf, unsigned len)
{
    if (self != g_tr) return g_usb_read(self, buf, len);
    for (;;) {
        ssize_t n = recv(g_fd, buf, len, 0);
        if (n > 0) {
            if (g_rx == 0) wb_logf("first bytes from the phone (%ld)", (long)n);
            g_rx += (unsigned long)n;
            return (int)n;
        }
        if (n < 0 && errno == EINTR) continue;
        wb_logf("read: connection closed (%s) after %lu bytes in, %lu out",
                n == 0 ? "by the relay" : strerror(errno), g_rx, g_tx);
        return -1;
    }
}

static int wb_write(void *self, void *buf, unsigned len)
{
    ssize_t n;
    int flags = 0;

    if (self != g_tr) return g_usb_write(self, buf, len);
#ifdef MSG_NOSIGNAL
    flags = MSG_NOSIGNAL;
#endif
    n = send(g_fd, buf, len, flags);
    if (n >= 0) {
        if (g_tx == 0) wb_logf("first bytes to the phone (%ld)", (long)n);
        g_tx += (unsigned long)n;
        return (int)n;
    }
    if (errno == EINTR || errno == EAGAIN) return -2;
    wb_logf("write failed: %s", strerror(errno));
    return -1;
}

static void wb_stop(void *self)
{
    if (self != g_tr) { g_usb_stop(self); return; }
    wb_logf("stop requested by gal (%lu bytes in, %lu out)", g_rx, g_tx);
    (void)shutdown(g_fd, SHUT_RDWR);
}

static void wb_forget(void *self)
{
    pthread_mutex_lock(&g_wb_lock);
    if (self == g_tr) {
        wb_logf("transport destroyed; session over");
        if (g_fd >= 0) close(g_fd);
        g_fd = -1;
        g_tr = NULL;
    }
    pthread_mutex_unlock(&g_wb_lock);
}

static void wb_dtor(void *self) { wb_forget(self); g_usb_dtor(self); }
static void wb_dtor_del(void *self) { wb_forget(self); g_usb_dtor_del(self); }

/* CUsbdiTransport::init: ours for 250/250 with a socket waiting. */
static int wb_init(void *self, unsigned bus, unsigned dev, void *path)
{
    if (bus == WB_BUS && dev == WB_DEV) {
        int ok = 0;
        pthread_mutex_lock(&g_wb_lock);
        if (g_pending >= 0 && g_tr == NULL) {
            g_fd = g_pending;
            g_pending = -1;
            g_tr = self;
            g_rx = g_tx = 0;
            ok = 1;
        }
        pthread_mutex_unlock(&g_wb_lock);
        wb_logf("init for the Wi-Fi session: %s (transport %p)", ok ? "taken" : "no socket waiting", self);
        return ok;
    }
    return g_init_tramp(self, bus, dev, path);
}

static void wb_job(void *self, void *a, void *b, void *c)
{
    if (g_recv == NULL) {
        g_recv = self;
        wb_logf("receiver found at %p", self);
    }
    g_recv_job(self, a, b, c);
}

/* ---- the listener ------------------------------------------------------ */

static int wb_hotspot_addr(struct in_addr *out)
{
    struct ifaddrs *list = NULL, *i;
    int found = 0;

    if (getifaddrs(&list) != 0) return 0;
    for (i = list; i != NULL; i = i->ifa_next) {
        if (i->ifa_addr && i->ifa_addr->sa_family == AF_INET && i->ifa_name &&
            strcmp(i->ifa_name, "uap0") == 0) {
            *out = ((struct sockaddr_in *)(void *)i->ifa_addr)->sin_addr;
            found = 1;
            break;
        }
    }
    freeifaddrs(list);
    return found;
}

static void wb_sleep_ms(long ms)
{
    struct timespec t;
    t.tv_sec = ms / 1000;
    t.tv_nsec = (ms % 1000) * 1000000L;
    while (nanosleep(&t, &t) != 0 && errno == EINTR) { }
}

static void *wb_listen(void *arg)
{
    const char *p = getenv("GAL_WIRELESS_BENCH_PORT");
    int port = p && *p ? atoi(p) : WB_PORT_DEFAULT;
    struct sockaddr_in sa;
    int s = -1, one = 1, tries = 0;

    (void)arg;
    /* The hotspot comes up some seconds after gal. */
    memset(&sa, 0, sizeof(sa));
    while (!wb_hotspot_addr(&sa.sin_addr)) {
        if (tries++ == 0) wb_logf("waiting for the hotspot (uap0) to get an address");
        wb_sleep_ms(2000);
    }
    sa.sin_family = AF_INET;
    sa.sin_port = htons((uint16_t)port);
    for (;;) {
        s = socket(AF_INET, SOCK_STREAM, 0);
        if (s >= 0) {
            (void)setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
            if (bind(s, (struct sockaddr *)&sa, sizeof(sa)) == 0 && listen(s, 1) == 0) break;
            wb_logf("listen on %s:%d failed: %s; again in 5 s", inet_ntoa(sa.sin_addr), port, strerror(errno));
            close(s);
        }
        wb_sleep_ms(5000);
    }
    wb_logf("listening on %s:%d (hotspot only)", inet_ntoa(sa.sin_addr), port);

    for (;;) {
        struct sockaddr_in peer;
        socklen_t pl = sizeof(peer);
        unsigned char path[256] __attribute__((aligned(8)));
        int c, r, waited;

        c = accept(s, (struct sockaddr *)&peer, &pl);
        if (c < 0) {
            if (errno != EINTR) { wb_logf("accept failed: %s", strerror(errno)); wb_sleep_ms(1000); }
            continue;
        }
        wb_logf("relay connected from %s", inet_ntoa(peer.sin_addr));
        if (g_tr != NULL || g_pending >= 0) { wb_logf("a Wi-Fi session is already up; refused"); close(c); continue; }
        if (g_recv == NULL) { wb_logf("gal's receiver not seen yet; refused"); close(c); continue; }
        (void)setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        pthread_mutex_lock(&g_wb_lock);
        g_pending = c;
        pthread_mutex_unlock(&g_wb_lock);

        memset(path, 0, sizeof(path));
        g_ustr_ctor(path);
        r = g_connect(g_recv, WB_BUS, WB_DEV, path, 0);
        g_ustr_dtor(path);
        wb_logf("processConnectGAL returned %d", r);

        /* The worker calls init on its own thread; give it 10 s. */
        for (waited = 0; waited < 100 && g_pending == c; ++waited) wb_sleep_ms(100);
        pthread_mutex_lock(&g_wb_lock);
        if (g_pending == c) {
            g_pending = -1;
            pthread_mutex_unlock(&g_wb_lock);
            wb_logf("gal never asked for the transport; closed (see gal's own log)");
            close(c);
            continue;
        }
        pthread_mutex_unlock(&g_wb_lock);
        wb_logf("session handed to gal after %d ms", waited * 100);
    }
    return NULL;
}

/* ---- installing -------------------------------------------------------- */

static uint32_t wb_word(uint32_t addr) { return *(volatile uint32_t *)(uintptr_t)addr; }

/* Jump from init to wb_init; the trampoline runs init's first two
 * instructions (the second, a PC-relative load, with its value copied) and
 * jumps back after them. Same steps as the CarPlay hook's
 * install_arm_hook_expected (thirdparty/mhi2_altscreen_carplay): never
 * writable and executable at once, and a private copy of the page when
 * the text mapping refuses write. */
static int wb_patch_init(const wb_layout *l)
{
    uint32_t *src = (uint32_t *)(uintptr_t)l->init;
    long ps = sysconf(_SC_PAGESIZE);
    uintptr_t page;
    uint32_t *tr;
    uint32_t lit = wb_word(l->init + 8u + (l->init_w1 & 0xfffu));

    if (ps <= 0) return -1;
    page = (uintptr_t)src & ~((uintptr_t)ps - 1u);
    tr = mmap(NULL, 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (tr == MAP_FAILED) { wb_logf("trampoline mmap failed: %s", strerror(errno)); return -1; }
    tr[0] = l->init_w0;               /* push {r4-fp, lr} */
    tr[1] = 0xe59f4004u;              /* ldr r4, [pc, #4]  -> tr[4] */
    tr[2] = 0xe51ff004u;              /* ldr pc, [pc, #-4] -> tr[3] */
    tr[3] = l->init + 8u;
    tr[4] = lit;
    __builtin___clear_cache((char *)tr, (char *)tr + 20);
    if (mprotect(tr, 32, PROT_READ | PROT_EXEC) != 0) {
        wb_logf("trampoline mprotect failed: %s", strerror(errno));
        munmap(tr, 32);
        return -1;
    }
    if (mprotect((void *)page, (size_t)ps, PROT_READ | PROT_WRITE) != 0) {
        unsigned char *copy = malloc((size_t)ps);
        void *fixed;
        wb_logf("text page not writable (%s); using a private copy", strerror(errno));
        if (copy == NULL) { munmap(tr, 32); return -1; }
        memcpy(copy, (const void *)page, (size_t)ps);
        fixed = mmap((void *)page, (size_t)ps, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
        if (fixed == MAP_FAILED || fixed != (void *)page) {
            wb_logf("private copy failed: %s", strerror(errno));
            free(copy);
            munmap(tr, 32);
            return -1;
        }
        memcpy(fixed, copy, (size_t)ps);
        free(copy);
    }
    src[0] = 0xe51ff004u;             /* ldr pc, [pc, #-4] -> src[1] */
    src[1] = (uint32_t)(uintptr_t)&wb_init;
    __builtin___clear_cache((char *)src, (char *)src + 8);
    if (mprotect((void *)page, (size_t)ps, PROT_READ | PROT_EXEC) != 0)
        wb_logf("text page back to read-only failed: %s (the patch is in)", strerror(errno));
    g_init_tramp = (wb_init_fn)(uintptr_t)tr;
    wb_logf("init patched: %#x -> %p, stock code via %p (literal %#x)", l->init, (void *)&wb_init, (void *)tr, lit);
    return 0;
}

/* QNX: /proc/self/exefile holds the program's path. */
static long wb_exe_size(void)
{
    char path[256];
    struct stat st;
    size_t n;
    FILE *f = fopen("/proc/self/exefile", "r");

    if (f == NULL) return -1;
    n = fread(path, 1, sizeof(path) - 1, f);
    fclose(f);
    while (n > 0 && (path[n - 1] == '\n' || path[n - 1] == '\0')) --n;
    path[n] = '\0';
    if (n == 0 || stat(path, &st) != 0) return -1;
    return (long)st.st_size;
}

static const wb_layout *wb_match(void)
{
    unsigned i;
    void *uv = dlsym(RTLD_DEFAULT, "_ZTVN3gal15CUsbdiTransportE");
    void *rv = dlsym(RTLD_DEFAULT, "_ZTVN3gal12CGALReceiverE");
    long size = wb_exe_size();

    for (i = 0; i < sizeof(k_layouts) / sizeof(k_layouts[0]); ++i) {
        const wb_layout *l = &k_layouts[i];
        uint32_t uvp = l->usb_vtable + 8u, rvp = l->recv_vtable + 8u;
        if ((uint32_t)(uintptr_t)uv != l->usb_vtable || (uint32_t)(uintptr_t)rv != l->recv_vtable) continue;
        if (size != (long)l->file_size) continue;
        if (wb_word(uvp) != l->usb_dtor || wb_word(uvp + 4u) != l->usb_dtor_del ||
            wb_word(uvp + 8u) != l->usb_stop || wb_word(uvp + 0xcu) != l->usb_read ||
            wb_word(uvp + 0x10u) != l->usb_write || wb_word(rvp + 0x28u) != l->recv_job) continue;
        if (wb_word(l->init) != l->init_w0 || wb_word(l->init + 4u) != l->init_w1) continue;
        if (wb_word(l->connect) != l->connect_w0 || wb_word(l->connect + 4u) != l->connect_w1) continue;
        return l;
    }
    wb_logf("no match: gal %ld bytes, CUsbdiTransport vtable %p, CGALReceiver vtable %p; nothing patched",
            size, uv, rv);
    return NULL;
}

static void wb_start(void)
{
    const wb_layout *l;
    uint32_t uvp, rvp;
    struct sigaction sa;
    pthread_t t;
    pthread_attr_t at;

    if (!environment_flag("GAL_WIRELESS_BENCH")) return;
    g_wb_log = open(WB_LOG_PATH, O_WRONLY | O_CREAT | O_APPEND, 0644);
    wb_logf("wireless bench test starting (hook %s, gal pid %ld)", GAL_HOOK_BUILD, (long)getpid());
    gal_hook_logf("event=wireless_bench result=starting log=%s", WB_LOG_PATH);
    l = wb_match();
    if (l == NULL) { gal_hook_logf("event=wireless_bench result=no_match"); return; }
    g_ustr_ctor = (wb_ustr_fn)dlsym(RTLD_DEFAULT, "_ZN4util14UnicodeString8C1Ev");
    g_ustr_dtor = (wb_ustr_fn)dlsym(RTLD_DEFAULT, "_ZN4util14UnicodeString8D1Ev");
    if (g_ustr_ctor == NULL || g_ustr_dtor == NULL) { wb_logf("util::UnicodeString8 not found; nothing patched"); return; }

    /* The trampoline first: if it fails, nothing else is changed. */
    if (wb_patch_init(l) != 0) { wb_logf("init not patched; nothing else changed"); return; }
    g_wb = l;
    g_connect = (wb_connect_fn)(uintptr_t)l->connect;
    uvp = l->usb_vtable + 8u;
    rvp = l->recv_vtable + 8u;
    g_usb_dtor = (wb_obj_fn)(uintptr_t)l->usb_dtor;
    g_usb_dtor_del = (wb_obj_fn)(uintptr_t)l->usb_dtor_del;
    g_usb_stop = (wb_obj_fn)(uintptr_t)l->usb_stop;
    g_usb_read = (wb_io_fn)(uintptr_t)l->usb_read;
    g_usb_write = (wb_io_fn)(uintptr_t)l->usb_write;
    g_recv_job = (wb_job_fn)(uintptr_t)l->recv_job;
    /* gal's writable data segment: no mprotect needed. */
    *(volatile uint32_t *)(uintptr_t)(uvp + 0x00u) = (uint32_t)(uintptr_t)&wb_dtor;
    *(volatile uint32_t *)(uintptr_t)(uvp + 0x04u) = (uint32_t)(uintptr_t)&wb_dtor_del;
    *(volatile uint32_t *)(uintptr_t)(uvp + 0x08u) = (uint32_t)(uintptr_t)&wb_stop;
    *(volatile uint32_t *)(uintptr_t)(uvp + 0x0cu) = (uint32_t)(uintptr_t)&wb_read;
    *(volatile uint32_t *)(uintptr_t)(uvp + 0x10u) = (uint32_t)(uintptr_t)&wb_write;
    *(volatile uint32_t *)(uintptr_t)(rvp + 0x28u) = (uint32_t)(uintptr_t)&wb_job;
    wb_logf("patched for %s", l->name);

    /* A write to a closed socket must not end gal. */
#ifndef MSG_NOSIGNAL
    if (sigaction(SIGPIPE, NULL, &sa) == 0 && sa.sa_handler == SIG_DFL) {
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = SIG_IGN;
        (void)sigaction(SIGPIPE, &sa, NULL);
        wb_logf("SIGPIPE ignored");
    }
#else
    (void)sa;
#endif
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &at, wb_listen, NULL) != 0) wb_logf("listener thread failed");
    pthread_attr_destroy(&at);
    gal_hook_logf("event=wireless_bench result=armed profile=%s", l->name);
}
