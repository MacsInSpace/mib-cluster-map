#ifndef GAL_HOOK_H
#define GAL_HOOK_H

#include <stddef.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gal_secondary_config {
    unsigned width;
    unsigned height;
    unsigned fps;
    unsigned codec;       /* 1 = H.264/AVC in the GAL video protocol */
    unsigned displayable_id; /* custom QNX EGL window; VcMOST uses 3 */
    unsigned vc_display;     /* dmdt sc/sb display id for the VC: 4, NOT the
                              * 1 that `dmdt gs` prints as its index */
    unsigned context_id;     /* Display Manager context; this unit uses 70 */
    unsigned restore_displayable_id; /* stock Kombi map window, 33 */
    unsigned service_id;    /* 0 = select the first free ID after primary */
    unsigned display_id;    /* AAP display_id; cluster is 1 */
    unsigned dpi;
    unsigned viewing_distance;
    unsigned pixel_aspect_ratio_e4;
    unsigned insets_top;
    unsigned insets_bottom;
    unsigned insets_left;
    unsigned insets_right;
    unsigned ui_theme;
    unsigned ui_config_payload_len;
    unsigned char ui_config_payload[16];
    /* Margins inside the coded frame that the phone leaves empty; the player
     * crops them off. High-resolution modes leave cockpit-window pixels. */
    unsigned margin_width;
    unsigned margin_height;
} gal_secondary_config;

int gal_hook_init(const gal_secondary_config *config);
void gal_hook_log(const char *message);
void gal_hook_logf(const char *format, ...);
void gal_hook_debugf(const char *format, ...);
int gal_hook_is_enabled(void);
int gal_hook_is_debug(void);
/*
 * Independent bisect switches for the 2026-08-22 SERVICE_DISCOVERY_MISSING
 * result: the phone stopped answering discovery once the hook both added a
 * second video service AND injected unknown display fields. Those two
 * changes were confounded. Both default ON, so behaviour is unchanged
 * unless explicitly disabled.
 *   GAL_DUALSCREEN_SECOND_SINK=0  -> do not build/register the second sink
 *   GAL_DUALSCREEN_INJECT_META=0  -> do not write the display_id/type fields
 */
int gal_hook_second_sink_enabled(void);
int gal_hook_inject_meta_enabled(void);
/*
 * AAP minor version to advertise. Defaults to 2, the stock value, so an
 * unset environment changes nothing. GAL_DUALSCREEN_AAP_MINOR=7 makes the
 * receiver claim 1.7, which is what Google's DHU negotiates.
 */
unsigned gal_hook_aap_minor(void);
int gal_hook_aap_minor_overridden(void);
/*
 * Advertise a cluster InputSourceService (display id 1) beside the
 * secondary video sink. Proven necessary against DHU; defaults OFF so it
 * can be enabled deliberately together with --aap-minor.
 */
int gal_hook_cluster_input_enabled(void);
/*
 * Output mode: what to do with the secondary sink's video.
 *
 *   withhold  Do not forward playbackStart to GAL. The sink stays registered
 *             and frames arrive via handleDataAvailable, are ACKed, and are
 *             forwarded over Unix socket to stream-player
 *             (/tmp/gal_video.sock).
 *             Main screen untouched. This is the only production path.
 *
 *   gal       Forward playbackStart to GAL. Stock path; reconfigures the
 *             one shared CVideoRenderer and blanks the main screen.
 *             Kept for diagnostic comparison only.
 */
enum {
    GAL_OUTPUT_GAL = 0,
    GAL_OUTPUT_WITHHOLD
};
int gal_hook_output_mode(void);
/*
 * Acknowledge decoded frames back to the phone ourselves.
 *
 * MediaSinkBase::ackFrames(session, count) is what tells the phone a frame
 * was consumed. In withhold mode GAL never acks the secondary stream, so
 * the hook acks every frame itself. Defaults ON, GAL_DUALSCREEN_ACK=0
 * disables (useful when measuring how long the phone tolerates silence).
 */
int gal_hook_frame_ack_enabled(void);
int gal_hook_focus_mirror_enabled(void);
int gal_hook_main_input_id_enabled(void);
const char *gal_hook_output_mode_name(void);
const gal_secondary_config *gal_hook_config(void);
/*
 * Isolated fixes from the 2026-09-15 Unix-socket car test. Each defaults ON;
 * setting its key to 0 in the environment or gal_dualscreen.conf runs the
 * previous code for that fix only. Every action a fix takes is logged with
 * fix=<name>, and init logs one event=fix.config line with all values.
 * hook_fix_enabled() reports the effective value: FOCUS_CONTROL needs
 * withhold output and GAL_STREAM_ENABLE, and ACK_RENDERED_ONLY and
 * NO_IDR_REPLAY need FOCUS_CONTROL.
 */
typedef enum {
    HOOK_FIX_HELPER_INIT_GUARD = 0, /* GAL_FIX_HELPER_INIT_GUARD: processes GAL spawns skip hook init */
    HOOK_FIX_FOCUS_CONTROL,         /* GAL_FOCUS_CONTROL: secondary held in focus mode 2 until the player is ready */
    HOOK_FIX_ACK_RENDERED_ONLY,     /* GAL_FIX_ACK_RENDERED_ONLY: only player render ACKs reach the phone */
    HOOK_FIX_NO_IDR_REPLAY,         /* GAL_FIX_NO_IDR_REPLAY: no codec-config/IDR replay or withholding on accept */
    HOOK_FIX_STREAM_TIMING,         /* GAL_FIX_STREAM_TIMING: send and send->ACK timing log every 30 frames */
    HOOK_FIX_PLAYER_LOG,            /* GAL_FIX_PLAYER_LOG: spawn() the player with its output in /tmp/stream-player.log */
    HOOK_FIX_ORPHAN_RESTORE,        /* GAL_FIX_ORPHAN_RESTORE: find orphan players by lock; restore the display after killing one */
    HOOK_FIX_COUNT
} hook_fix;
int hook_fix_enabled(hook_fix fix);
/*
 * GAL_SECONDARY_MAX_UNACKED: how many cluster frames the phone may have sent
 * and not yet had ACKed (the max_unacked of the secondary sink's setup
 * answer). Every frame in flight waits in front of the player's decoder, so
 * this bounds how far the cockpit map can lag. 8 by default, 4 with
 * GAL_ACK_EVERY_FRAME=1; 1 to 16.
 */
unsigned gal_hook_max_unacked(void);
/*
 * GAL_ACK_EVERY_FRAME=1: the player ACKs every frame (drawn, replaced before
 * it was drawn, or giving no picture), the hook stops presuming frames
 * dropped, puts an access unit delimiter after each frame, and the phone's
 * window is 4 instead of 8. AMDFX60's 1.4.0: the cockpit map in step with
 * the centre screen on a Skoda Superb. Off by default; both sides read it.
 */
int gal_hook_ack_every_frame(void);
/*
 * GAL_DEBUG_PRIMARY=1: log each centre-screen (primary) video start and, 5 s
 * later, whether its frames came (event=primary.check), and tell the player
 * through /tmp/clustermap-primary-start. GAL_PRIMARY_RESTART_PAUSE_MS=N
 * (0..10000, implies the logging): the player stops decoding for N ms when
 * the centre screen's video restarts. Both off by default (#125, #145).
 */
int gal_hook_debug_primary(void);
unsigned gal_hook_restart_pause_ms(void);
/* GAL_FOCUS_START=stock lets gal's setup-time mode 1 through; default native. */
int gal_hook_focus_start_native(void);
/* GAL_FOCUS_WAIT_KOMBI: the first grant also waits for the Kombi map. */
int gal_hook_focus_wait_kombi(void);

#ifdef __cplusplus
}
#endif

#endif
