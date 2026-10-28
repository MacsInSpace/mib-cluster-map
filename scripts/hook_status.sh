#!/bin/sh

# A non-interactive shell -- ssh "host command", or anything not started
# from a login shell -- does not inherit the firmware's PATH, so dirname,
# wc, grep and the unit's own binaries are simply absent and this script
# fails in confusing ways partway through. Set it before any external
# command runs, including the dirname below.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

set -u

SCRIPT_DIR=`dirname "$0"`
CARD_ROOT=`cd "$SCRIPT_DIR/.." && pwd`
HOOK_LOG_SD="$CARD_ROOT/logs/gal_dualscreen.log"
HOOK_LOG_TMP=/tmp/gal_dualscreen.log
. "$SCRIPT_DIR/lib_resolve_hook_log.sh"

# Pass an explicit path as $1 to override the SD/tmp resolution below.
if [ -n "${1:-}" ]; then
    LOG=$1
else
    LOG=`resolve_hook_log`
fi

[ -r "$LOG" ] || {
    if [ -n "${1:-}" ]; then
        echo "Hook log is not available: $LOG" >&2
    else
        # resolve_hook_log() has to return something even when neither
        # candidate exists; don't let that guess read as "here's the log,
        # it's just unreadable" when the real situation is "neither
        # location has anything at all."
        echo "Hook log is not available at either candidate location:" >&2
        echo "  $HOOK_LOG_SD" >&2
        echo "  $HOOK_LOG_TMP" >&2
    fi
    exit 1
}

echo "GAL dual-screen key events: $LOG"
echo "============================================================"
grep \
    -e 'event=init ' \
    -e 'event=firmware.verify' \
    -e 'event=primary.register' \
    -e 'event=secondary.video_config' \
    -e 'event=secondary.output_patch' \
    -e 'event=secondary.register' \
    -e 'event=discovery.metadata' \
    -e 'event=discovery.rewrite' \
    -e 'event=kombi.ready' \
    -e 'event=focus.hold_wait' \
    -e 'event=aap.setup' \
    -e 'event=aap.media_config' \
    -e 'event=aap.video_focus' \
    -e 'event=nvss.open' \
    -e 'event=nvss.configure' \
    -e 'event=vc.route' \
    -e 'event=aap.playback' \
    -e 'event=nvss.close' \
    -e 'event=own.' \
    -e 'event=config.output' \
    -e 'event=aap.codec_config' \
    -e 'result=failed' \
    "$LOG" || true

DEBUG_ON=0
grep -q 'event=init .*debug=1' "$LOG" && DEBUG_ON=1

echo
echo "Recent secondary frame samples"
echo "============================================================"
if [ "$DEBUG_ON" -eq 1 ]; then
    # tail -20 folded into the capture itself, not applied after: a long
    # debug session can produce thousands of aap.frame lines (roughly one
    # per second of streaming), and only the last 20 are ever shown.
    FRAME_SAMPLES=`grep 'event=aap.frame role=secondary' "$LOG" | tail -20`
    if [ -n "$FRAME_SAMPLES" ]; then
        echo "$FRAME_SAMPLES"
    else
        echo "(debug logging is on; no secondary frame samples were recorded -- the secondary sink has not received data yet)"
    fi
else
    echo "(debug logging was not enabled for this run: GAL_DUALSCREEN_DEBUG=0 or unset."
    echo " Frame-level events are never written without it. An empty section here is"
    echo " NOT evidence of zero frames -- re-run with --debug, or rely on the"
    echo " player lines of the checklist below.)"
fi

# A [PASS] means the corresponding log line was found -- it confirms the
# internal step reported success, not that the cockpit screen is actually
# showing correct video. Check that visually as well.
check()
{
    label=$1
    pattern=$2
    if grep -q "$pattern" "$LOG"; then
        echo "[PASS] $label"
    else
        echo "[    ] $label"
    fi
}

# Like check(), but for events whose result is only ever logged as a raw
# integer/hex code rather than a pre-classified success/failed string, so
# this can only honestly report whether the stage was reached, not whether
# it succeeded. The matching line is printed so a human can judge the code.
reached()
{
    label=$1
    pattern=$2
    match=`grep "$pattern" "$LOG" | tail -1`
    if [ -n "$match" ]; then
        echo "[PASS] $label -- reached (see result code below; not independently confirmed which value means success)"
        echo "$match" | sed 's/^/       /'
    else
        echo "[    ] $label -- not reached"
    fi
}

echo
echo "Acceptance checklist"
echo "============================================================"
check   "hook enabled at startup"                       'event=init .*enabled=1'
check   "firmware ABI verified"                         'event=firmware.verify result=success'
check   "primary sink registered"                       'event=primary.register result=success'
check   "secondary sink registered"                     'event=secondary.register result=success'
# VWG11's receiver has no unknown-field strings, so its second display is
# announced by rewriting the encoded message (discovery.rewrite) instead.
check   "second display announced to the phone"         'event=discovery.metadata result=success role=secondary\|event=discovery.rewrite result=success'
reached "secondary AAP setup"                           'event=aap.setup.complete role=secondary'
reached "secondary AAP media configuration"             'event=aap.media_config role=secondary'
check   "cockpit showed its map view (window 33)"       'event=kombi.ready'
check   "cluster stream started for the player"         'event=aap.playback action=start role=secondary'
check   "frames acknowledged to the phone"              'event=own.ack count='

# The player writes its own log; it sits next to the hook log in a run_logs
# save, and in /tmp on the unit.
PLAYER_LOG=`dirname "$LOG"`/stream-player.log
[ -r "$PLAYER_LOG" ] || PLAYER_LOG=/tmp/stream-player.log
if [ -r "$PLAYER_LOG" ]; then
    for step in "first frame drawn" "cluster switched to the player"; do
        if grep -q "$step" "$PLAYER_LOG"; then
            echo "[PASS] player: $step"
        else
            echo "[    ] player: $step"
        fi
    done
else
    echo "[    ] player log not found ($PLAYER_LOG)"
fi

if grep -q 'event=focus.hold_wait reason=kombi_not_ready' "$LOG" && \
   ! grep -q 'event=kombi.ready' "$LOG"; then
    echo "[NOTE] the cockpit never showed its map view in this session, so the"
    echo "       player was never started. Switch the cockpit to the map view"
    echo "       (the car's own navigation map) and the phone's map takes over."
fi

# The own/own-ack output modes decode inside GAL into a private NvSS
# instance. The shipped mode is withhold (stream-player), so this section is
# only printed when one of those modes was actually used.
grep -q 'event=own\.\(open\|decode\|codec_config\|suppress\)' "$LOG" || OWN_MODE_UNUSED=1
if [ -z "${OWN_MODE_UNUSED:-}" ]; then
echo
echo "Own-decode path (GAL_DUALSCREEN_OUTPUT=own / own-ack)"
echo "------------------------------------------------------------"
MODE=`grep 'event=aap.playback action=start role=secondary output_mode=' "$LOG" | tail -1`
if [ -n "$MODE" ]; then
    echo "       $MODE"
else
    echo "       (no secondary playbackStart seen -- output mode unknown)"
fi
check   "private NvSS instance opened"                  'event=own.open result=ok'
check   "codec config (SPS/PPS) captured"               'event=own.codec_config result=stored'
# Either ordering counts: replay happens when the config arrived before
# our decoder existed, submit_live when it arrived after -- and the DHU
# capture shows the phone actually sends MediaStartRequest first, so
# submit_live is the expected one.
check   "codec config fed to our decoder"              'event=own.codec_config action=\(replay\|submit_live\).*result=ok'
reached "first frame submitted to our decoder"          'event=own.decode result=first_ok'
check   "payload is Annex-B aligned"                    'event=own.decode result=first_ok.*annexb=yes'
check   "frames acknowledged to the phone"              'event=own.ack count='
# own-ack only; a mismatch here means the hook REFUSED to patch and fell
# back to withholding, which is the safe outcome but not the intended test.
if grep -q 'event=own.suppress' "$LOG"; then
    check   "renderer job suppressed via private vtable" 'event=own.suppress result=ok'
    if grep -q 'event=own.suppress result=unsupported' "$LOG"; then
        echo "[NOTE] own-ack is not available for the secondary sink: this hook"
        echo "       puts a CVideoSinkImpl at sink+0x38, so playbackStart"
        echo "       dispatches through a different vtable than the one own-ack"
        echo "       stubs. The run fell back to 'own', which is the safe path."
    fi
    if grep -q 'event=own.suppress result=fail reason=vtable_mismatch' "$LOG"; then
        echo "[WARN] handler vtable did not match the expected address --"
        echo "       suppression was refused and the run fell back to 'own'."
        grep 'event=own.suppress result=fail' "$LOG" | tail -1 | sed 's/^/       /'
    fi
fi
if grep -q 'event=vc.route action=skip' "$LOG"; then
    echo "[WARN] cockpit route was skipped -- no decoder was live at frame 2"
    grep 'event=vc.route action=skip' "$LOG" | tail -1 | sed 's/^/       /'
fi
FAILS=`grep -c 'event=own.decode result=fail' "$LOG" 2>/dev/null || true`
NOPAY=`grep -c 'event=own.decode result=no_payload' "$LOG" 2>/dev/null || true`
echo "       decode rejections: $FAILS   payload-extraction misses: $NOPAY"
ACKS=`grep -c 'event=own.ack count=' "$LOG" 2>/dev/null || true`
echo "       ack log lines: $ACKS (logged at 1,2,3 then every 300th)"
fi

echo
echo "This checklist reflects what the hook's own log claims about itself. It"
echo "does not confirm the decoded image on the physical cockpit screen is"
echo "correct, or that the primary/main-HMI screen is unaffected -- verify"
echo "both visually before treating a run as validated."
