/* mib-cluster-map iAP2 Route Guidance capability negotiation, USB observer,
 * state reducer, and /tmp/clustermap-rgd.state publisher for AU57x HUD/cluster.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dlfcn.h>
#include <pthread.h>
#include <time.h>
#include "rgd_wire.h"
#include "rgd_monitor.h"
#include "rgd_packet.h"
#include "rgd_state.h"

#ifndef RGD_DISABLE_TMP
#define RGD_DISABLE_TMP "/tmp/clustermap-rgd.disabled"
#endif
#ifndef RGD_DISABLE_PERSIST
#define RGD_DISABLE_PERSIST "/mnt/app/eso/lib/gal_dualscreen/carplay_rgd_off"
#endif
#ifndef RGD_LOG
#define RGD_LOG "/tmp/clustermap-rgd.log"
#endif
#ifndef RGD_STATE_FILE
#define RGD_STATE_FILE "/tmp/clustermap-rgd.state"
#endif

typedef char pkt_storage_offset[(offsetof(struct rgd_native_packet, storage) == 24) ? 1 : -1];
typedef char pkt_control_offset[(offsetof(struct rgd_native_packet, control) == 36) ? 1 : -1];
typedef char pkt_length_offset[(offsetof(struct rgd_native_packet, payload_length) == 40) ? 1 : -1];

typedef int (*init_fn)(void *, char *);
typedef int (*ident_fn)(void *, struct rgd_native_packet *);
typedef int (*read_fn)(void *, void *, unsigned, int, unsigned);
typedef int (*send_fn)(void *, const void *, unsigned);
typedef int (*packet_fn)(void *);
struct ident_entry { uint32_t id; ident_fn callback; };
struct ctrl_msg_info { const char *name; uint32_t flags; const void *params; };
struct ctrl_msg_group { const char *name; const struct ctrl_msg_info *msgs; uint32_t count; };
static const struct ctrl_msg_info rgd_ctrl_msgs[5] = {
    { "StartRouteGuidanceUpdates",       1, NULL },
    { "RouteGuidanceUpdate",             2, NULL },
    { "RouteGuidanceManeuverUpdate",     2, NULL },
    { "StopRouteGuidanceUpdates",        1, NULL },
    { "RequestRouteGuidanceSourceName",  1, NULL }
};

static init_fn original_init;
static ident_fn original_ident;
static read_fn original_read;
static send_fn send_raw;
static packet_fn original_packet;
static struct rgd_monitor monitor;
static struct rgd_state g_state;
static uint64_t g_session = 1;
static unsigned g_seq = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int transport_ready, advertised, accepted, authenticated, sent, sending, rejected, got_520x;
static unsigned attempts, events;
static uint64_t last_5200_ms;

static uint64_t now_mono_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL;
}

static void log_line(const char *line) {
    int saved = errno, fd;
    char prefix[40];
    int length;
    if (events++ >= 8000) { errno = saved; return; }
    fd = open(RGD_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        length = snprintf(prefix, sizeof(prefix), "pid=%ld ", (long)getpid());
        write(fd, prefix, (size_t)length);
        write(fd, line, strlen(line));
        write(fd, "\n", 1);
        close(fd);
    }
    errno = saved;
}

static void write_state_file(void) {
    struct rgd_current cur;
    int active = rgd_state_current(&g_state, &cur);
    char buf[1536];
    int len, fd, saved = errno;
    int m_idx = (active && cur.has_maneuver) ? (int)cur.maneuver.index : -1;
    int m_type = (active && cur.has_maneuver && (cur.maneuver.present & RGD_M_TYPE)) ? (int)cur.maneuver.type : -1;
    int angle_present = (active && cur.has_maneuver && (cur.maneuver.present & RGD_M_ANGLE)) ? 1 : 0;
    int turn_angle = angle_present ? cur.maneuver.exit_angle : 1000;
    int junction_type = (active && cur.has_maneuver && (cur.maneuver.present & RGD_M_JUNCTION)) ? cur.maneuver.junction_type : -1;
    int driving_side = (active && cur.has_maneuver && (cur.maneuver.present & RGD_M_DRIVING)) ? cur.maneuver.driving_side : -1;
    int step_present = (active && cur.has_maneuver && (cur.maneuver.present & RGD_M_STEP_DIST)) ? 1 : 0;
    unsigned step_dist = step_present ? (unsigned)cur.maneuver.step_distance_m : 0u;
    const char *turn_road = (active && cur.has_maneuver) ? cur.maneuver.road : "";
    const char *turn_desc = (active && cur.has_maneuver) ? cur.maneuver.description : "";
    const char *exit_info = (active && cur.has_maneuver) ? cur.maneuver.exit : "";

    g_seq++;
    len = snprintf(buf, sizeof(buf),
        "seq=%u\n"
        "active=%d\n"
        "route_state=%d\n"
        "maneuver_state=%d\n"
        "source_support=%d\n"
        "visible_in_app=%d\n"
        "maneuver_idx=%d\n"
        "maneuver_type=%d\n"
        "turn_angle=%d\n"
        "angle_present=%d\n"
        "junction_type=%d\n"
        "driving_side=%d\n"
        "dist_m=%u\n"
        "dist_present=%d\n"
        "step_dist_m=%u\n"
        "step_dist_present=%d\n"
        "dest_dist_m=%u\n"
        "dest_dist_present=%d\n"
        "eta_sec=%llu\n"
        "eta_present=%d\n"
        "rem_sec=%llu\n"
        "rem_present=%d\n"
        "current_road=%s\n"
        "turn_road=%s\n"
        "turn_desc=%s\n"
        "exit_info=%s\n"
        "dest_name=%s\n"
        "source_name=%s\n",
        g_seq,
        active,
        g_state.route_known ? g_state.route_state : 0,
        g_state.maneuver_state,
        g_state.source_support,
        g_state.visible_in_app,
        m_idx,
        m_type,
        turn_angle,
        angle_present,
        junction_type,
        driving_side,
        (unsigned)g_state.distance_m,
        g_state.distance_known ? 1 : 0,
        step_dist,
        step_present,
        (unsigned)g_state.destination_distance_m,
        g_state.destination_distance_known ? 1 : 0,
        (unsigned long long)g_state.eta_seconds,
        g_state.eta_known ? 1 : 0,
        (unsigned long long)g_state.remaining_seconds,
        g_state.remaining_known ? 1 : 0,
        g_state.current_road,
        turn_road,
        turn_desc,
        exit_info,
        g_state.destination,
        g_state.source_name);
    if (len > 0 && (size_t)len < sizeof(buf)) {
        /* Write directly to RGD_STATE_FILE without rename(): on QNX 6.5 /tmp is a symlink
         * to /dev/shmem (procnto shared-memory object manager), which returns ENOSYS on rename(). */
        fd = open(RGD_STATE_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            if (write(fd, buf, (size_t)len) != len) {
                log_line("write_state_file: short write to " RGD_STATE_FILE);
            }
            close(fd);
        } else {
            log_line("write_state_file: failed to open " RGD_STATE_FILE);
        }
    }
    errno = saved;
}

static void reset_session_locked(const char *why) {
    accepted = 0;
    authenticated = 0;
    sent = 0;
    sending = 0;
    got_520x = 0;
    attempts = 0;
    last_5200_ms = 0;
    g_session++;
    rgd_state_reset(&g_state, 16, g_session, 1);
    write_state_file();
    if (why) log_line(why);
}

static void received(void *unused, const uint8_t *p, size_t n) {
    unsigned msg = ((unsigned)p[4] << 8) | p[5];
    struct rgd_event e;
    char line[2048];
    int len;
    unsigned i;
    (void)unused;
    if (msg == 0x1d00) {
        reset_session_locked("StartIdentification received; session state reset");
        return;
    }
    if (msg == 0x1d02) {
        accepted = 1;
        log_line("identification accepted; subscription pending");
        return;
    }
    if (msg == 0x1d03) {
        accepted = 0;
        advertised = 0;
        rejected = 1;
        log_line("identification rejected; next identification uses stock capabilities, no subscription");
        return;
    }
    if (msg == 0xaa05) {
        authenticated = 1;
        log_line("stock accessory authentication succeeded; guidance request permitted");
        return;
    }
    if (msg == 0xaa04) {
        authenticated = 0;
        log_line("stock accessory authentication failed; no guidance request");
        return;
    }
    if (msg < 0x5200 || msg > 0x5204) return;
    if (rgd_parse(p, n, &e) != 1) {
        log_line("guidance message rejected by parser; stock bytes unchanged");
        return;
    }
    len = snprintf(line, sizeof(line), "guidance msg=0x%04x bytes=%u present=%08x", msg, (unsigned)n, e.present);
    for (i = 0; i < 32 && len > 0 && (unsigned)len < sizeof(line) - 80; i++) {
        if (e.present & (1u << i)) {
            if (e.numeric & (1u << i))
                len += snprintf(line + len, sizeof(line) - (unsigned)len, " f%u=%llu", i, (unsigned long long)e.value[i]);
            else
                len += snprintf(line + len, sizeof(line) - (unsigned)len, " f%u[length=%u]", i, e.length[i]);
        }
    }
    log_line(line);
    {
        size_t at;
        for (at = 6; at < n;) {
            unsigned size = ((unsigned)p[at] << 8) | p[at + 1], id = ((unsigned)p[at + 2] << 8) | p[at + 3];
            if ((msg == 0x5201 && (id == 3 || id == 4 || id == 8 || id == 11 || id == 19)) ||
                (msg == 0x5202 && (id == 2 || id == 4 || id == 6 || id == 13))) {
                char value[161];
                unsigned j = 0;
                while (j < size - 4 && j < sizeof(value) - 1 && p[at + 4 + j]) {
                    unsigned c = p[at + 4 + j];
                    value[j] = (char)(c < 32 ? 32 : c);
                    j++;
                }
                value[j] = 0;
                snprintf(line, sizeof(line), "guidance text msg=0x%04x field=%u value=%s", msg, id, value);
                log_line(line);
            }
            at += size;
        }
    }
    if (msg == 0x5201 || msg == 0x5202 || msg == 0x5204) {
        got_520x = 1;
    }
    if (msg == 0x5201 || msg == 0x5202) {
        if (rgd_state_apply(&g_state, g_session, 1, p, n) == 1) {
            write_state_file();
        }
    }
}

static int capture_read(void *device, void *buffer, unsigned capacity, int timeout, unsigned flags) {
    int rc = original_read(device, buffer, capacity, timeout, flags), saved = errno;
    if (rc > 0 && (unsigned)rc <= capacity) {
        pthread_mutex_lock(&lock);
        rgd_monitor_feed(&monitor, buffer, (size_t)rc);
        pthread_mutex_unlock(&lock);
    }
    errno = saved;
    return rc;
}

static int receive_packet(void *context) {
    int result = original_packet(context), saved = errno, subscribe = 0, rc;
    unsigned attempt = 0;
    pthread_mutex_lock(&lock);
    if (result >= 0 && transport_ready && advertised && accepted && authenticated && !got_520x && !sending && attempts < 120) {
        uint64_t now = now_mono_ms();
        uint64_t gap = (attempts == 0) ? 0ULL : ((attempts < 5) ? 2000ULL : 10000ULL);
        if (attempts == 0 || last_5200_ms == 0 || now == 0 || (now >= last_5200_ms && (now - last_5200_ms) >= gap)) {
            attempt = ++attempts;
            last_5200_ms = now;
            sending = 1;
            subscribe = 1;
        }
    }
    pthread_mutex_unlock(&lock);
    if (subscribe) {
        /* 0x5200 StartRouteGuidanceUpdates:
         *  param 0 (ComponentID = 16)
         *  param 1 (ShowExitAngle = none/flag)
         *  param 2 (SupportSourceName = none/flag)
         *  param 3 (SupportRouteGuidanceManeuverCapacity = none/flag)
         * Keep the 24-byte packet that iOS ACKs on C7.5, retrying periodically until 0x5201/0x5202 arrives. */
        static const uint8_t request[] = {
            0x40, 0x40, 0, 24, 0x52, 0,
            0, 6, 0, 0, 0, 16,
            0, 4, 0, 1,
            0, 4, 0, 2,
            0, 4, 0, 3
        };
        char line[96];
        rc = send_raw(context, request, sizeof(request));
        pthread_mutex_lock(&lock);
        sending = 0;
        if (rc == 0) sent = 1;
        snprintf(line, sizeof(line), "subscription request rc=%d attempt=%u", rc, attempt);
        log_line(line);
        pthread_mutex_unlock(&lock);
    }
    errno = saved;
    return result;
}

static int identify(void *context, struct rgd_native_packet *packet) {
    int rc = original_ident(context, packet), saved = errno, allow;
    pthread_mutex_lock(&lock);
    allow = !rejected;
    pthread_mutex_unlock(&lock);
    if (rc == 0 && transport_ready && allow) {
        int changed = rgd_packet_identify(packet, 16);
        pthread_mutex_lock(&lock);
        advertised = changed;
        log_line(changed ? "route-guidance capability appended; original identity retained"
                         : "capability append refused; stock identification retained");
        pthread_mutex_unlock(&lock);
    } else if (rc == 0 && !allow) {
        pthread_mutex_lock(&lock);
        advertised = 0;
        log_line("fallback: original stock identification retained");
        pthread_mutex_unlock(&lock);
    }
    errno = saved;
    return rc;
}

static int initialize(void *context, char *options) {
    void *device = NULL;
    uintptr_t *transport = NULL;
    Dl_info info;
    read_fn candidate;
    int rc;
    pthread_mutex_lock(&lock);
    rejected = 0;
    advertised = 0;
    reset_session_locked("iap2_init: new session starting");
    pthread_mutex_unlock(&lock);

    memcpy(&device, (uint8_t *)context + 20, sizeof(device));
    if (!device) return original_init(context, options);
    memcpy(&transport, (uint8_t *)device + 64, sizeof(transport));
    if (!transport || !transport[0] || strcmp((const char *)transport[0], "ipod_transport"))
        return original_init(context, options);
    candidate = (read_fn)transport[11];
    if (candidate == capture_read && original_read != NULL) {
        pthread_mutex_lock(&lock);
        rgd_monitor_init(&monitor, received, NULL);
        transport_ready = 1;
        log_line("USB receive observer already active on transport");
        pthread_mutex_unlock(&lock);
        return original_init(context, options);
    }
    memset(&info, 0, sizeof(info));
    if (!candidate || !dladdr((void *)candidate, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "ipod-transport-usbdevice.so")) {
        log_line("unsupported transport; route guidance disabled");
        return original_init(context, options);
    }
    pthread_mutex_lock(&lock);
    original_read = candidate;
    rgd_monitor_init(&monitor, received, NULL);
    transport[11] = (uintptr_t)capture_read;
    transport_ready = 1;
    log_line("USB receive observer installed; data and return values delegated unchanged");
    pthread_mutex_unlock(&lock);
    rc = original_init(context, options);
    if (rc != 0) {
        int saved = errno;
        pthread_mutex_lock(&lock);
        transport[11] = (uintptr_t)candidate;
        transport_ready = 0;
        log_line("native initialization failed; observer removed");
        pthread_mutex_unlock(&lock);
        errno = saved;
    }
    return rc;
}

void rgd_install(void *handle, uintptr_t *driver) {
    struct ident_entry *table;
    int init_slot = -1, pkt_slot = -1, ident_slot = -1, i;
    char line[160];

    if (access(RGD_DISABLE_TMP, F_OK) == 0 || access(RGD_DISABLE_PERSIST, F_OK) == 0) {
        log_line("route-guidance adapter disabled by marker; delegating stock");
        return;
    }
    table = (struct ident_entry *)dlsym(handle, "ident_info_funcs");
    original_init = (init_fn)dlsym(handle, "iap2_init");
    send_raw = (send_fn)dlsym(handle, "link_send_raw_message");
    original_packet = (packet_fn)dlsym(handle, "transport_recv_pkt");
    if (!table || !original_init || !send_raw || !original_packet) {
        log_line("native symbol lookup failed; route guidance disabled");
        return;
    }
    for (i = 1; i < 16; i++) {
        if (!driver[i]) continue;
        if (driver[i] == (uintptr_t)original_init) init_slot = i;
        if (driver[i] == (uintptr_t)original_packet) pkt_slot = i;
    }
    if (table[6].id == 6 && table[7].id == 7) {
        for (i = 8; i < 32; i++) {
            if (!table[i].callback) break;
            ident_slot = i;
        }
    }
    if (init_slot < 0 || pkt_slot < 0 || ident_slot < 0 || !table[ident_slot].callback) {
        snprintf(line, sizeof(line),
            "native ABI mismatch (init_slot=%d pkt_slot=%d ident_slot=%d); route guidance disabled",
            init_slot, pkt_slot, ident_slot);
        log_line(line);
        return;
    }
    rgd_state_reset(&g_state, 16, g_session, 1);
    write_state_file();
    {
        struct ctrl_msg_group *ctrl_table = (struct ctrl_msg_group *)dlsym(handle, "iap2_ctrl_msg_table");
        if (ctrl_table) {
            ctrl_table[0x52].name = "RouteGuidance";
            ctrl_table[0x52].msgs = rgd_ctrl_msgs;
            ctrl_table[0x52].count = 5;
            log_line("registered 0x5200..0x5204 in iap2_ctrl_msg_table[0x52]");
        } else {
            log_line("WARNING: iap2_ctrl_msg_table symbol not found");
        }
    }
    original_ident = table[ident_slot].callback;
    table[ident_slot].callback = identify;
    driver[init_slot] = (uintptr_t)initialize;
    driver[pkt_slot] = (uintptr_t)receive_packet;
    snprintf(line, sizeof(line),
        "route-guidance adapter installed (init_slot=%d pkt_slot=%d ident_slot=%d id=%u)",
        init_slot, pkt_slot, ident_slot, (unsigned)table[ident_slot].id);
    log_line(line);
}

