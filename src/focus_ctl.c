#include "focus_ctl.h"
#include "gal_hook.h"
#include "vc_player_mgr.h"
#include "vc_stream_out.h"

#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <time.h>

/*
 * The controller runs on events: a frame to send, an ACK, a player
 * connecting or going away, and gal's thread posting a setup, start, stop or
 * focus write. Otherwise it steps at the next deadline below, and at least
 * once every 2.5 seconds for the two things nothing signals: the channel-open byte and
 * a player that dies before it has connected.
 */
#define FC_IDLE_STEP_MS        2500LL
#define FC_STOP_WAIT_MS        1500LL  /* MediaStop followed mode 2 in 0.16-0.83 s on the car */
#define FC_OWN_STOP_WINDOW_MS  5000LL
#define FC_MAILBOX_FALLBACK_MS 300LL   /* gal's thread ran 22 of 24 writes within 0.28 s */
/* Long enough for the player to put the Kombi map back itself; see
 * vc_player_stop_wait. Only stopping players wait here, never a stream. */
#define FC_PLAYER_STOP_GRACE_MS 3000
/*
 * A player that is alive and connected but renders nothing for this long is
 * stuck. Not a few seconds: a slow player under load is not a dead one, and
 * every replacement costs the session -- the phone streams 3.3 fps afterwards
 * and resets USB ~122 s later (car, 2026-09-16).
 */
#define FC_HANG_MS             20000LL
#define FC_HEALTHY_MS          30000LL  /* surviving this long clears the failures */
#define FC_HEALTHY_ACK_MS      1000LL   /* ...while still rendering: an ACK this recent */
#define FC_BACKOFF_MIN_MS      1000LL
#define FC_BACKOFF_MAX_MS      10000LL
/*
 * After this many player deaths with no healthy session in between, stop
 * spawning until the phone reconnects. A player that has failed five times
 * is not going to work on the sixth, and each attempt is another crash and
 * another core dump in /mnt/ota.
 */
#define FC_SPAWN_LIMIT         5u
#define FC_RING                64u
/*
 * Leaked-credit backstop (see release_leaked): how long the stream must have
 * been quiet, and how many outstanding frames are left alone. With
 * GAL_ACK_EVERY_FRAME=1 the player ACKs every frame, so this should never
 * fire.
 */
#define FC_MAX_OUTSTANDING     4u     /* old accounting (GAL_ACK_EVERY_FRAME off) */
#define FC_LEAK_QUIET_MS       3000LL
#define FC_LEAK_KEEP           1u
#define FC_LATENCY_LOG_MS      60000LL  /* ack.latency line while stream_timing is off */
#define FC_HOLD_NO_LISTENER    0x100u   /* hold_wait log keys, distinct from the grant mask */
#define FC_HOLD_GAVE_UP        0x200u
#define FC_HOLD_PHONE_NATIVE   0x400u

typedef enum { FC_IDLE = 0, FC_HOLD, FC_GRANTED, FC_ACTIVE } fc_state;
static const char *const k_state_name[] = { "IDLE", "HOLD", "GRANTED", "ACTIVE" };

static void *g_sink;
static fc_ops g_ops;
static pthread_t g_thread;
static int g_started;
static volatile int g_run;

/*
 * Shared with gal's reader thread, under g_lock. The lock is a leaf: never
 * held across a gal call, a spawn, a socket wait or a sleep.
 */
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
/*
 * Serialises the stock setVideoFocus call itself. g_lock cannot: it is
 * released before the call so it stays a leaf, which leaves gal's reader
 * thread and the controller free to marshal on the same endpoint at once.
 */
static pthread_mutex_t g_write_lock = PTHREAD_MUTEX_INITIALIZER;
static fc_state g_state = FC_IDLE;
static int g_in_setup;
static int g_mode_sent = -1;        /* last focus mode written for the secondary */
static long long g_mode2_ms;        /* when it last changed to 2 */
static int g_own_stop_seen;
static int g_stop_required;
static int g_teardown_requested;
static int g_new_setup;
static int g_late_stop;
static int g_mb_pending;            /* one slot: the newest intent wins */
static int g_mb_mode;
static long long g_mb_posted_ms;
static const char *g_mb_reason = "";
static long long g_ring[FC_RING];   /* send times of delivered, unACKed frames */
static unsigned g_ring_head;
static unsigned g_ring_count;
static unsigned long g_ring_overflow;
static unsigned long g_lat_sum_ms;
static unsigned g_lat_max_ms;
static unsigned g_lat_count;
static unsigned long g_discarded_acks;
static unsigned long g_leaked_released;
static unsigned long g_presumed_dropped;
static int g_phone_wants_native;

/* Controller thread only. */
static long long g_spawn_ms = -1;
static long long g_backoff_until_ms;
static long long g_backoff_ms;
static unsigned long g_spawn_accepts;
static unsigned long g_spawn_ack_accepts;
static long long g_grant_ms;
static long long g_last_ack_ms;
static int g_ack_was_connected;
static int g_gate_was_open;
static unsigned g_hold_logged = ~0u;
static int g_kombi_wait_logged;
static int g_healthy_seen;
static unsigned g_spawn_failures;
static int g_player_given_up;
static unsigned g_pending_acks;
static volatile int g_dirty;        /* another thread wants a step now */

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000L);
}

/* g_lock held */
static void ring_reset_locked(void)
{
    g_ring_head = 0u;
    g_ring_count = 0u;
}

/* g_lock held */
static void set_state_locked(fc_state next, const char *reason)
{
    if (g_state == next) return;
    gal_hook_logf("event=focus.state from=%s to=%s reason=%s fix=focus_control",
                  k_state_name[g_state], k_state_name[next], reason);
    g_state = next;
}

/* g_lock held */
static void post_focus_locked(int mode, const char *reason)
{
    g_mb_pending = 1;
    g_mb_mode = mode;
    g_mb_posted_ms = now_ms();
    g_mb_reason = reason;
}

/* g_lock held */
static void note_mode_locked(int mode, long long now)
{
    if (mode == 2 && g_mode_sent != 2) {
        g_mode2_ms = now;
        g_own_stop_seen = 0;
    }
    g_mode_sent = mode;
}

/*
 * Focus writes run on gal's reader thread from the routeMessage hook, the
 * thread stock GAL answers focus from. The controller sends a write itself
 * only if no message has been routed for FC_MAILBOX_FALLBACK_MS.
 */
static void run_mailbox(const char *via, long long min_age_ms)
{
    int mode;
    long long now = now_ms();
    long long queued;
    const char *reason;

    pthread_mutex_lock(&g_lock);
    if (!g_mb_pending || now - g_mb_posted_ms < min_age_ms) {
        pthread_mutex_unlock(&g_lock);
        return;
    }
    g_mb_pending = 0;
    mode = g_mb_mode;
    reason = g_mb_reason;
    queued = now - g_mb_posted_ms;
    note_mode_locked(mode, now);
    pthread_mutex_unlock(&g_lock);

    pthread_mutex_lock(&g_write_lock);
    g_ops.set_focus(g_sink, mode, 1);
    pthread_mutex_unlock(&g_write_lock);
    gal_hook_logf("event=focus.write mode=%d unconstrained=1 reason=%s via=%s queued_ms=%lld fix=focus_control",
                  mode, reason, via, queued);
}

/* Pops at most the number of delivered frames; the rest are not the phone's. */
static unsigned take_acks(unsigned count)
{
    unsigned n;
    unsigned i;
    unsigned discard;
    unsigned long total;
    long long now = now_ms();

    pthread_mutex_lock(&g_lock);
    n = count < g_ring_count ? count : g_ring_count;
    for (i = 0u; i < n; ++i) {
        long long age = now - g_ring[g_ring_head];
        unsigned ms = age < 0 ? 0u : (unsigned)age;
        g_lat_sum_ms += ms;
        if (ms > g_lat_max_ms) g_lat_max_ms = ms;
        ++g_lat_count;
        g_ring_head = (g_ring_head + 1u) % FC_RING;
    }
    g_ring_count -= n;
    discard = count - n;
    g_discarded_acks += discard;
    total = g_discarded_acks;
    pthread_mutex_unlock(&g_lock);

    if (!hook_fix_enabled(HOOK_FIX_ACK_RENDERED_ONLY)) return count;
    if (discard != 0u && (total <= 5ul || total % 100ul < discard))
        gal_hook_logf("event=ack.discard count=%u total=%lu state=%s fix=ack_rendered_only",
                      discard, total, fc_state_name());
    return n;
}

/*
 * GAL_ACK_EVERY_FRAME off (the default, as up to v1.2.8): the player ACKs only
 * the frames it draws, and its pool overwrites an unconsumed frame when its
 * render loop is behind, so a dropped frame never produces an ACK. As ACKs
 * arrive, credit beyond FC_MAX_OUTSTANDING (plus the hook's own queue) is
 * presumed dropped and returned, or the phone's window would close for good.
 * With a slow decoder those frames were often only waiting, which is the lag
 * the other mode removes (below).
 */
static unsigned reconcile_dropped(void)
{
    unsigned released = 0u;
    unsigned limit = FC_MAX_OUTSTANDING + vc_stream_out_queue_depth();

    pthread_mutex_lock(&g_lock);
    while (g_ring_count > limit) {
        g_ring_head = (g_ring_head + 1u) % FC_RING;
        --g_ring_count;
        ++released;
    }
    g_presumed_dropped += released;
    pthread_mutex_unlock(&g_lock);
    if (released != 0u)
        gal_hook_logf("event=ack.presumed_dropped count=%u total=%lu fix=ack_rendered_only",
                      released, g_presumed_dropped);
    return released;
}

static void reconcile_on_ack(void)
{
    unsigned released;
    int active;

    if (gal_hook_ack_every_frame()) return;
    if (!hook_fix_enabled(HOOK_FIX_ACK_RENDERED_ONLY) || g_ops.frames_rendered == 0)
        return;
    pthread_mutex_lock(&g_lock);
    active = (g_state == FC_ACTIVE);
    pthread_mutex_unlock(&g_lock);
    if (!active) return;
    released = reconcile_dropped();
    if (released != 0u) g_ops.frames_rendered(released);
}

/*
 * GAL_ACK_EVERY_FRAME=1 (AMDFX60's 1.4.0). Credit for frames the player never ACKs. Up to 1.4.0-beta1 the hook
 * guessed them: as ACKs came in, everything beyond 4 outstanding frames
 * (plus its own queue) was taken as dropped by the player's pool and its
 * credit returned. But once the 720p decoder became the slowest step, the
 * frames beyond 4 were not dropped at all, only waiting in the loopback
 * socket (about 130 KB each way, and a cluster frame is mostly 0.1-5 KB).
 * Every returned credit let the phone send one more frame into that queue:
 * 79 "presumed dropped" in 3.5 minutes on the Superb (2026-11-12) where the
 * player had dropped about 13, which left the cockpit map 2-3 s behind the
 * centre screen.
 *
 * The player now ACKs every frame itself (drawn, replaced before it was
 * drawn, or giving no picture), so nothing is guessed while frames flow.
 * This only catches a leak should one still happen: once the stream has
 * been quiet for FC_LEAK_QUIET_MS -- nothing delivered, no ACK -- and the
 * player's last ACK came after the last frame reached it, the player has
 * had everything and stopped by itself, so anything still outstanding
 * beyond FC_LEAK_KEEP will never be ACKed. A stuck player has not ACKed
 * since the last delivery; that stays the hang rule's case.
 */
static unsigned release_leaked(long long now, long long last_ack_ms)
{
    unsigned released = 0u;
    long long newest;

    pthread_mutex_lock(&g_lock);
    if (g_ring_count > FC_LEAK_KEEP) {
        newest = g_ring[(g_ring_head + g_ring_count - 1u) % FC_RING];
        if (now - newest >= FC_LEAK_QUIET_MS && now - last_ack_ms >= FC_LEAK_QUIET_MS &&
            last_ack_ms >= newest) {
            while (g_ring_count > FC_LEAK_KEEP) {
                g_ring_head = (g_ring_head + 1u) % FC_RING;
                --g_ring_count;
                ++released;
            }
            g_leaked_released += released;
        }
    }
    pthread_mutex_unlock(&g_lock);
    if (released != 0u)
        gal_hook_logf("event=ack.leak_released count=%u total=%lu fix=ack_rendered_only",
                      released, g_leaked_released);
    return released;
}

/*
 * Return the phone's credit for every delivered frame still outstanding, and
 * empty the ring. Every frame the phone sends must be ACKed exactly once --
 * by the player, by the leak backstop, or here -- because the phone never forgets an
 * unACKed frame: its window does not reset on MediaStop/MediaStart.
 * On the car (run 3, 2026-09-16) seven entries discarded across one player
 * replacement left it a single slot, and it trickled 3.3 fps for the rest of
 * the session. Not used on a new setup or a closed channel, where the window
 * starts over anyway.
 *
 * Never with g_lock held: frames_rendered marshals ackFrames on gal's router.
 */
static void flush_credits(const char *why)
{
    unsigned n;

    pthread_mutex_lock(&g_lock);
    n = g_ring_count;
    ring_reset_locked();
    pthread_mutex_unlock(&g_lock);
    if (n == 0u || !hook_fix_enabled(HOOK_FIX_ACK_RENDERED_ONLY) ||
        g_ops.frames_rendered == 0)
        return;
    g_ops.frames_rendered(n);
    gal_hook_logf("event=ack.credit_returned count=%u reason=%s fix=ack_rendered_only",
                  n, why);
}

static void teardown_player(const char *reason)
{
    gal_hook_logf("event=focus.teardown reason=%s fix=focus_control", reason);
    vc_player_stop_wait(FC_PLAYER_STOP_GRACE_MS);
    vc_stream_out_begin_stream();
    g_spawn_ms = -1;
    g_ack_was_connected = 0;
}

/*
 * Every recovery is the same: back to mode 2, replace the player, wait a
 * little longer each time. There is no separate dead state -- HOLD with a
 * long backoff already means "native, not spawning", and a latch that has to
 * be escaped is one more way to leave the cluster dark.
 */
static void handle_loss(long long now, const char *reason, int stop_player)
{
    /* Only when the player goes: one that keeps running still owes ACKs for
     * the frames in its decode queue, and will send them. A player being
     * replaced never will, so return that credit first -- before the mode 2
     * goes out, so the phone's window is whole when it restarts. */
    if (stop_player) flush_credits(reason);
    pthread_mutex_lock(&g_lock);
    /* Already native when a player dies before its grant: nothing to tell the
     * phone, and a redundant write is one more message on its channel. */
    if (g_mode_sent != 2) {
        post_focus_locked(2, reason);
        g_stop_required = 1;
    }
    set_state_locked(FC_HOLD, reason);
    pthread_mutex_unlock(&g_lock);

    if (stop_player) {
        long long lifetime = g_spawn_ms >= 0 ? now - g_spawn_ms : -1;
        ++g_spawn_failures;
        teardown_player(reason);
        long long after_teardown = now_ms();
        g_backoff_ms = g_backoff_ms == 0 ? FC_BACKOFF_MIN_MS : g_backoff_ms * 2;
        if (g_backoff_ms > FC_BACKOFF_MAX_MS) g_backoff_ms = FC_BACKOFF_MAX_MS;
        g_backoff_until_ms = after_teardown + g_backoff_ms;
        gal_hook_logf("event=focus.loss reason=%s player=stopped lifetime_ms=%lld failures=%u retry_ms=%lld fix=focus_control",
                      reason, lifetime, g_spawn_failures, g_backoff_ms);
        if (g_spawn_failures >= FC_SPAWN_LIMIT && !g_player_given_up) {
            g_player_given_up = 1;
            /* The map is already back: the player restored it on its way
             * out, or vc_player_stop / vc_player_poll did after a SIGKILL or
             * a crash. */
            gal_hook_logf("event=focus.player_given_up failures=%u until=next_session fix=focus_control",
                          g_spawn_failures);
        }
    } else {
        g_backoff_until_ms = 0;
        gal_hook_logf("event=focus.loss reason=%s player=kept failures=%u fix=focus_control",
                      reason, g_spawn_failures);
    }
    g_hold_logged = ~0u;
}

static void grant(long long now, int own_stop, int stop_required)
{
    vc_stream_out_require_keyframe();
    pthread_mutex_lock(&g_lock);
    /* No ring reset here: the player may still owe ACKs for frames delivered
     * before this grant. The phone's own MediaStart resets it. */
    post_focus_locked(1, "grant");
    set_state_locked(FC_GRANTED, "grant");
    g_stop_required = 0;
    pthread_mutex_unlock(&g_lock);
    g_grant_ms = now;
    g_last_ack_ms = now;
    g_healthy_seen = 0;
    g_ack_was_connected = vc_stream_out_ack_client_connected();
    gal_hook_logf("event=focus.grant player_age_ms=%lld ack_client=%d after=%s fix=focus_control",
                  now - g_spawn_ms, g_ack_was_connected,
                  own_stop ? "media_stop" : (stop_required ? "stop_wait" : "immediate"));
}

static void hold_step(long long now, int gate, int mode_sent, long long mode2_ms, int own_stop, int stop_required)
{
    int stream;
    int ack;
    int stop_ok;
    unsigned mask;

    if (gal_hook_focus_wait_kombi() && !vc_kombi_ready()) {
        if (!g_kombi_wait_logged) {
            g_kombi_wait_logged = 1;
            gal_hook_log("event=focus.hold_wait reason=kombi_not_ready fix=focus_control");
        }
        return;
    }

    if (!vc_stream_out_listening()) {
        /*
         * The listener can fail to bind when something else holds the path
         * (the 2026-09-15 socket steal). vc_stream_out latches that failure,
         * and only a frame write retries it -- but frames need a grant, and a
         * grant needs a connected player. Retry here instead.
         */
        if (vc_stream_out_open() != 0) {
            if (g_hold_logged != FC_HOLD_NO_LISTENER) {
                g_hold_logged = FC_HOLD_NO_LISTENER;
                gal_hook_log("event=focus.hold_wait reason=no_video_listener fix=focus_control");
            }
            return;
        }
        g_hold_logged = ~0u;
    }

    if (g_player_given_up) {
        /* Nothing more to try until the phone reconnects. The cluster keeps
         * its own map and the phone is not asked to stream to a dead end. */
        if (g_hold_logged != FC_HOLD_GAVE_UP) {
            g_hold_logged = FC_HOLD_GAVE_UP;
            gal_hook_logf("event=focus.hold_wait reason=player_given_up failures=%u fix=focus_control",
                          g_spawn_failures);
        }
        return;
    }

    if (!vc_player_poll()) {
        if (g_spawn_ms >= 0) {
            handle_loss(now, "player_exit_before_grant", 1);
            return;
        }
        if (now < g_backoff_until_ms) return;
        g_spawn_accepts = vc_stream_out_accept_count();
        g_spawn_ack_accepts = vc_stream_out_ack_accept_count();
        vc_player_start();
        g_spawn_ms = now_ms();
        g_hold_logged = ~0u;
        return;
    }

    stream = vc_stream_out_is_connected() &&
             vc_stream_out_accept_count() > g_spawn_accepts;
    /* Rendered-only ACKs travel on this socket, so a grant without it would
     * start a stream nothing can acknowledge. It connected 1.2-1.5 s after
     * the spawn on the car, 17 times out of 17. */
    ack = (vc_stream_out_ack_client_connected() &&
           vc_stream_out_ack_accept_count() > g_spawn_ack_accepts) ||
          !hook_fix_enabled(HOOK_FIX_ACK_RENDERED_ONLY);
    stop_ok = !stop_required || own_stop || now - mode2_ms >= FC_STOP_WAIT_MS;
    if (g_phone_wants_native) {
        if (g_hold_logged != FC_HOLD_PHONE_NATIVE) {
            g_hold_logged = FC_HOLD_PHONE_NATIVE;
            gal_hook_log("event=focus.hold_wait reason=phone_requested_native fix=focus_control");
        }
        return;
    }
    mask = (mode_sent == 2 ? 1u : 0u) | ((unsigned)stream << 1) |
           ((unsigned)ack << 2) | ((unsigned)stop_ok << 3) | ((unsigned)gate << 4);
    if (mask != 0x1fu) {
        if (mask != g_hold_logged) {
            g_hold_logged = mask;
            gal_hook_logf("event=focus.hold_wait mode=%d stream=%d ack=%d stop=%d gate=%d fix=focus_control",
                          mode_sent, stream, ack, stop_ok, gate);
        }
        return;
    }
    grant(now, own_stop, stop_required);
}

static void active_step(long long now, fc_state state, unsigned ring_count)
{
    const char *loss = 0;

    if (!vc_player_poll()) loss = "player_exit";
    else if (!vc_stream_out_is_connected()) loss = "stream_disconnect";
    else if (vc_stream_out_ack_client_connected()) g_ack_was_connected = 1;
    else if (g_ack_was_connected) loss = "ack_disconnect";

    /*
     * Two or more delivered frames outstanding and no ACK at all for the
     * budget. One outstanding frame is not a hang: the stream can go quiet
     * with the newest frame not yet ACKed.
     */
    if (loss == 0 && ring_count >= 2u && now - g_last_ack_ms >= FC_HANG_MS)
        loss = "hang";
    if (loss != 0) {
        handle_loss(now, loss, 1);
        return;
    }
    if (state == FC_ACTIVE && gal_hook_ack_every_frame() &&
        hook_fix_enabled(HOOK_FIX_ACK_RENDERED_ONLY) && g_ops.frames_rendered != 0) {
        unsigned released = release_leaked(now, g_last_ack_ms);
        if (released != 0u) g_ops.frames_rendered(released);
    }
    if (state == FC_ACTIVE && !g_healthy_seen && now - g_grant_ms >= FC_HEALTHY_MS &&
        now - g_last_ack_ms <= FC_HEALTHY_ACK_MS) {
        /* A session that has streamed this long must not inherit an old
         * player's backoff. */
        g_healthy_seen = 1;
        g_backoff_ms = 0;
        g_spawn_failures = 0u;
        gal_hook_logf("event=focus.healthy elapsed_ms=%lld fix=focus_control", now - g_grant_ms);
    }
}

static void step(long long now)
{
    fc_state state;
    int teardown;
    int new_setup;
    int late_stop;
    int mode_sent;
    int own_stop;
    int stop_required;
    long long mode2_ms;
    unsigned ring_count;
    int gate = g_sink != 0 && ((const unsigned char *)g_sink)[4] != 0;


    run_mailbox("controller", FC_MAILBOX_FALLBACK_MS);

    pthread_mutex_lock(&g_lock);
    state = g_state;
    teardown = g_teardown_requested;
    g_teardown_requested = 0;
    new_setup = g_new_setup;
    g_new_setup = 0;
    late_stop = g_late_stop;
    g_late_stop = 0;
    mode_sent = g_mode_sent;
    mode2_ms = g_mode2_ms;
    own_stop = g_own_stop_seen;
    stop_required = g_stop_required;
    ring_count = g_ring_count;
    pthread_mutex_unlock(&g_lock);

    if (new_setup) {
        g_spawn_failures = 0u;
        g_player_given_up = 0;
        g_backoff_ms = 0;
        g_backoff_until_ms = 0;
        g_kombi_wait_logged = 0;
        g_hold_logged = ~0u;
    }
    if (teardown) teardown_player("new_setup");

    if (gate) {
        g_gate_was_open = 1;
    } else if (g_gate_was_open) {
        g_gate_was_open = 0;
        if (state != FC_IDLE) {
            gal_hook_logf("event=focus.session_end reason=channel_closed state=%s fix=focus_control",
                          k_state_name[state]);
            teardown_player("channel_closed");
            pthread_mutex_lock(&g_lock);
            /* A new setup might have arrived while teardown_player blocked. */
            if (!g_new_setup) {
                g_mb_pending = 0;
                g_mode_sent = -1;
                ring_reset_locked();
                set_state_locked(FC_IDLE, "channel_closed");
            }
            pthread_mutex_unlock(&g_lock);
        }
        return;
    }

    switch (state) {
    case FC_HOLD:
        hold_step(now, gate, mode_sent, mode2_ms, own_stop, stop_required);
        break;
    case FC_GRANTED:
    case FC_ACTIVE:
        if (late_stop) handle_loss(now, "late_stop", 0);
        else active_step(now, state, ring_count);
        break;
    default:
        break;
    }
}

/*
 * Time to the next thing only a clock can trigger: a focus write gal's thread
 * has not picked up, the stop wait after our mode 2, and the respawn backoff.
 * (Kombi readiness arrives as an event.) FC_IDLE_STEP_MS when none is due
 * sooner.
 */
static int next_step_in(long long now)
{
    long long wait = FC_IDLE_STEP_MS;
    long long d;

    pthread_mutex_lock(&g_lock);
    if (g_mb_pending) {
        d = g_mb_posted_ms + FC_MAILBOX_FALLBACK_MS - now;
        if (d < wait) wait = d;
    }
    if (g_state == FC_HOLD && g_mode_sent == 2 && g_stop_required && !g_own_stop_seen) {
        d = g_mode2_ms + FC_STOP_WAIT_MS - now;
        if (d > 0 && d < wait) wait = d;
    }
    pthread_mutex_unlock(&g_lock);
    if (g_backoff_until_ms > now) {
        d = g_backoff_until_ms - now;
        if (d < wait) wait = d;
    }
    return wait > 0 ? (int)wait : 0;
}

/*
 * Once a minute while streaming: how long a frame took from reaching the
 * hook to the player's ACK (drawn or replaced), i.e. how far the cockpit
 * map runs behind what the phone sent. With fix=stream_timing on, its own
 * line every 30 frames reports the same and this one stays quiet.
 */
static void log_latency(long long now)
{
    static long long next_ms;
    unsigned avg_ms, max_ms, unacked, n;

    if (hook_fix_enabled(HOOK_FIX_STREAM_TIMING)) return;
    if (next_ms == 0) { next_ms = now + FC_LATENCY_LOG_MS; return; }
    if (now < next_ms) return;
    next_ms = now + FC_LATENCY_LOG_MS;
    n = fc_take_latency(&avg_ms, &max_ms, &unacked);
    if (n != 0u)
        gal_hook_logf("event=ack.latency frames=%u avg_ms=%u max_ms=%u unacked=%u window=%u fix=ack_rendered_only",
                      n, avg_ms, max_ms, unacked, gal_hook_max_unacked());
}

static void on_acks(unsigned count)
{
    g_pending_acks += count;
}

static void *controller_main(void *arg)
{
    sigset_t all;
    long long next_step = 0;
    (void)arg;

    /* No signal is for this thread; the player gets an empty mask at spawn. */
    sigfillset(&all);
    (void)pthread_sigmask(SIG_BLOCK, &all, 0);
    gal_hook_log("event=focus.controller result=started fix=focus_control");

    while (g_run) {
        long long now = now_ms();
        int wait_ms = next_step > now ? (int)(next_step - now) : 0;
        int changed;

        g_pending_acks = 0u;
        changed = vc_stream_out_wait(wait_ms, on_acks);
        if (g_pending_acks != 0u) {
            unsigned n = take_acks(g_pending_acks);
            if (n != 0u) {
                g_last_ack_ms = now_ms();
                /*
                 * frames_rendered marshals MediaSinkBase::ackFrames onto
                 * gal's router, the same endpoint a focus write uses, so it
                 * takes g_write_lock -- inside ack_secondary_frame, once per
                 * ACK. Taking it here as well would deadlock the controller
                 * on the first ACK. (Nothing can serialise us against gal's
                 * own sends; this only orders our two threads.)
                 */
                if (g_ops.frames_rendered != 0) g_ops.frames_rendered(n);
                reconcile_on_ack();
                log_latency(g_last_ack_ms);
            }
        }
        now = now_ms();
        if (changed || g_dirty || now >= next_step) {
            g_dirty = 0;
            step(now);
            now = now_ms();
            next_step = now + next_step_in(now);
        }
    }
    gal_hook_log("event=focus.controller result=stopped fix=focus_control");
    return 0;
}

int fc_enabled(void)
{
    return g_started;
}

void fc_notify(void)
{
    if (!g_started) return;
    g_dirty = 1;
    vc_stream_out_wake();
}

/*
 * Exported so the hook's own ACK path can take the same lock: with
 * GAL_FIX_ACK_RENDERED_ONLY=0 gal's reader thread ACKs too, and it must not
 * marshal on this sink while the controller is doing the same.
 */
void fc_write_lock(void)
{
    if (g_started) pthread_mutex_lock(&g_write_lock);
}

void fc_write_unlock(void)
{
    if (g_started) pthread_mutex_unlock(&g_write_lock);
}

void fc_start(void *secondary_sink, const fc_ops *ops)
{
    int rc;

    if (g_started || secondary_sink == 0 || ops == 0 || ops->set_focus == 0 ||
        !hook_fix_enabled(HOOK_FIX_FOCUS_CONTROL))
        return;
    g_sink = secondary_sink;
    g_ops = *ops;
    (void)vc_stream_out_open();
    /* Before any player exists, so its ACK connect always finds a listener. */
    (void)vc_stream_out_ack_init();
    if (gal_hook_focus_wait_kombi()) vc_kombi_watch_start();
    g_run = 1;
    rc = pthread_create(&g_thread, 0, controller_main, 0);
    if (rc != 0) {
        g_run = 0;
        gal_hook_logf("event=focus.start result=failed rc=%d fallback=legacy fix=focus_control", rc);
        return;
    }
    g_started = 1;
    gal_hook_logf("event=focus.start result=ok sink=%p start=%s wait_kombi=%d fix=focus_control",
                  secondary_sink, gal_hook_focus_start_native() ? "native" : "stock",
                  gal_hook_focus_wait_kombi());
}

void fc_shutdown(void)
{
    if (!g_started) return;
    g_run = 0;
    (void)pthread_join(g_thread, 0);
    g_started = 0;
}

void fc_setup_begin(void *sink)
{
    fc_state previous;

    if (!g_started || sink != g_sink) return;
    pthread_mutex_lock(&g_lock);
    previous = g_state;
    g_in_setup = 1;
    g_phone_wants_native = 0;
    if (previous == FC_GRANTED || previous == FC_ACTIVE) g_teardown_requested = 1;
    g_new_setup = 1;
    g_stop_required = (previous == FC_GRANTED || previous == FC_ACTIVE);
    g_mb_pending = 0;
    g_mode_sent = -1;
    g_own_stop_seen = 0;
    g_late_stop = 0;
    ring_reset_locked();
    set_state_locked(FC_HOLD, "setup");
    pthread_mutex_unlock(&g_lock);
    gal_hook_logf("event=focus.setup previous=%s start=%s wait_kombi=%d fix=focus_control",
                  k_state_name[previous],
                  gal_hook_focus_start_native() ? "native" : "stock",
                  gal_hook_focus_wait_kombi());
    fc_notify();
}

void fc_setup_end(void *sink)
{
    if (!g_started || sink != g_sink) return;
    pthread_mutex_lock(&g_lock);
    g_in_setup = 0;
    pthread_mutex_unlock(&g_lock);
}

int fc_filter_focus(void *sink, int *mode)
{
    int held = 0;

    if (!g_started || sink != g_sink || mode == 0) return 0;
    pthread_mutex_lock(&g_lock);
    if (g_in_setup && *mode == 1 && gal_hook_focus_start_native()) {
        *mode = 2;
        held = 1;
    }
    note_mode_locked(*mode, now_ms());
    pthread_mutex_unlock(&g_lock);
    return held;
}

/*
 * The phone asking for mode 2 is the user leaving projection. Answering 1
 * anyway denies it, the phone stops the stream, we re-grant, it stops again --
 * a livelock at the stop-wait interval. Honour the request, and do not grant
 * again until the phone asks for projection or a new session starts.
 */
int fc_request_reply(void *sink, int requested)
{
    int mode;

    if (!g_started || sink != g_sink) return -1;
    pthread_mutex_lock(&g_lock);
    if (requested == 2) {
        g_phone_wants_native = 1;
        mode = 2;
    } else {
        g_phone_wants_native = 0;
        mode = (g_state == FC_GRANTED || g_state == FC_ACTIVE) ? 1 : 2;
    }
    /*
     * This answer supersedes any queued intent. Without this a grant posted
     * moments earlier still fires from the next routed message and writes
     * mode 1 microseconds after the phone was told native.
     */
    g_mb_pending = 0;
    note_mode_locked(mode, now_ms());
    pthread_mutex_unlock(&g_lock);
    /* Same lock as every other focus write: two threads must not marshal on
     * one endpoint. */
    pthread_mutex_lock(&g_write_lock);
    g_ops.set_focus(sink, mode, 0);
    pthread_mutex_unlock(&g_write_lock);
    fc_notify();
    return mode;
}

void fc_playback_start(void *sink)
{
    fc_state state;
    const char *action = "none";

    if (!g_started || sink != g_sink) return;
    pthread_mutex_lock(&g_lock);
    state = g_state;
    /*
     * The phone streaming again is the phone wanting projection, whatever it
     * asked for earlier -- and this hold has never been seen to arm on the
     * car (no focus request appears in any capture), so it must not be able
     * to strand the cluster on an unobserved path.
     */
    g_phone_wants_native = 0;
    if (state == FC_GRANTED) {
        set_state_locked(FC_ACTIVE, "playback_start");
        action = "active";
    } else if (state != FC_ACTIVE) {
        /* e.g. GAL_FOCUS_START=stock: the stream is not ours yet. */
        post_focus_locked(2, "start_not_granted");
        if (state == FC_IDLE) set_state_locked(FC_HOLD, "start_without_setup");
        action = "hold_native";
    }
    pthread_mutex_unlock(&g_lock);
    /* Anything still outstanding belongs to the stream before this one. */
    flush_credits("playback_start");
    gal_hook_logf("event=focus.playback_start state=%s action=%s fix=focus_control",
                  k_state_name[state], action);
    fc_notify();
}

int fc_playback_stop(void *sink)
{
    int ours = 0;
    int late = 0;
    long long now = now_ms();

    if (!g_started || sink != g_sink) return 0;
    pthread_mutex_lock(&g_lock);
    /*
     * Ours only if we had already stepped back to HOLD for it. Testing the
     * last mode written was wrong twice over: gal writes mode 2 on this sink
     * itself, and a stop arriving while we are still ACTIVE cannot be the
     * answer to a mode 2 we never sent.
     */
    if (g_state == FC_HOLD && g_mode_sent == 2 &&
        now - g_mode2_ms <= FC_OWN_STOP_WINDOW_MS) {
        g_own_stop_seen = 1;
        ours = 1;
    } else if (g_state == FC_GRANTED || g_state == FC_ACTIVE) {
        g_late_stop = 1;
        late = 1;
    }
    pthread_mutex_unlock(&g_lock);
    /*
     * ACK, do not just forget: the phone does NOT reset its window on
     * MediaStop/MediaStart (the earlier assumption that it did is what leaked
     * the credits in run 3). Emptying the ring also keeps the next grant from
     * looking 3 s stale to the hang rule.
     */
    flush_credits("playback_stop");
    gal_hook_logf("event=focus.playback_stop ours=%d late=%d state=%s fix=focus_control",
                  ours, late, fc_state_name());
    fc_notify();
    return ours;
}

void fc_frame_delivered(void)
{
    long long now = now_ms();

    pthread_mutex_lock(&g_lock);
    if (g_ring_count == FC_RING) {
        /*
         * Keep the oldest entry rather than the newest. Its age is what the
         * hang rule measures, so dropping it would hide the very stall that
         * filled the ring -- and the phone keeps at most its window of
         * unACKed frames in flight (GAL_SECONDARY_MAX_UNACKED, 16 at most),
         * so a full 64-entry ring already means nothing is being rendered.
         */
        unsigned long overflow = ++g_ring_overflow;
        pthread_mutex_unlock(&g_lock);
        if (overflow == 1ul || overflow % 100ul == 0ul)
            gal_hook_logf("event=ack.ring_full dropped=%lu state=%s fix=ack_rendered_only",
                          overflow, fc_state_name());
        return;
    }
    g_ring[(g_ring_head + g_ring_count) % FC_RING] = now;
    ++g_ring_count;
    pthread_mutex_unlock(&g_lock);
}

void fc_run_mailbox(void)
{
    /* Unlocked peek: this runs for every routed message. */
    if (!g_started || !g_mb_pending) return;
    run_mailbox("gal_thread", 0);
}

unsigned fc_take_latency(unsigned *avg_ms, unsigned *max_ms, unsigned *unacked)
{
    unsigned n;

    pthread_mutex_lock(&g_lock);
    n = g_lat_count;
    *avg_ms = n != 0u ? (unsigned)(g_lat_sum_ms / n) : 0u;
    *max_ms = g_lat_max_ms;
    *unacked = g_ring_count;
    g_lat_count = 0u;
    g_lat_sum_ms = 0ul;
    g_lat_max_ms = 0u;
    pthread_mutex_unlock(&g_lock);
    return n;
}

const char *fc_state_name(void)
{
    return k_state_name[g_state];
}
