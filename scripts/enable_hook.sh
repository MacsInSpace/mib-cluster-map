#!/bin/sh

# A non-interactive shell -- ssh "host command", or anything not started
# from a login shell -- does not inherit the firmware's PATH, so dirname,
# wc, grep and the unit's own binaries are simply absent and this script
# fails in confusing ways partway through. Set it before any external
# command runs, including the dirname below.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

# Install the preload environment into the supervisor-owned GAL child.
# This script never launches a second GAL process.

set -eu

CARD_ROOT=`cd "\`dirname "$0"\`" && pwd`
SYSTEM_MOUNT=/mnt/system
TARGET_CONFIG=$SYSTEM_MOUNT/etc/eso/production/smartphone_integrator.json
PERSISTENT_BACKUP=$TARGET_CONFIG.gal-dualscreen.original
JSONLINT=/mnt/app/eso/bin/jsonlint
# Match the QNX login/startup loader path. In particular, libiplcommon.so,
# libosal.so, and libutil.so are supplied by /lib, not /mnt/app/eso/lib.
VALIDATOR_LD_LIBRARY_PATH=/proc/boot:/lib:/lib/dll:/usr/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib:/eso/lib:/mnt/app/eso/lib
BACKUP_DIR="$CARD_ROOT/backups"
ORIGINAL="$BACKUP_DIR/smartphone_integrator.json.original"
LOG_DIR="$CARD_ROOT/logs"
DPI=140
DEBUG=0
SECOND_SINK=1
INJECT_META=1
AAP_MINOR=
CLUSTER_INPUT=1
OUTPUT=withhold
DISPLAYABLE=
LOG_PATH_REQUESTED=
STREAM=1
SYSTEM_WRITABLE=0
SYSTEM_TEMP=
KEEP_TBT=0
KEEP_NAVIGNORE=0
CARPLAY=1
# The CarPlay map: harman-f's cluster-stream hook (in libcarplay_cluster.so)
# patches functions of this exact CarPlay library, so it is installed only on
# a unit whose libairplay.so has this size (SHA-256 193a4fd9...46b5 on MU1440
# and MU1367). The hook also checks the function prologues itself and leaves
# CarPlay stock on a mismatch.
AIRPLAY_LIB=/mnt/app/eso/lib/libairplay.so
AIRPLAY_SIZE=703688
CARPLAY_PRELOAD=/mnt/app/eso/lib/gal_dualscreen/libcarplay_cluster.so
CARPLAY_OK=0

# The preload target lives on the internal /mnt/app partition instead of the
# SD card. The SD card mounts read-only again on every fresh boot unless
# something remounts it before GAL starts; unlike the hook's own log path,
# there is no automatic fallback for a missing LD_PRELOAD target -- the
# dynamic linker just silently proceeds without it, so if the SD card is not
# yet mounted at the exact moment smartphone_integrator launches GAL, the
# hook never loads at all, with no error anywhere. See lib_app_mount.sh
# (shared with disable_hook.sh) for the path constants and why /eso/lib
# was chosen over /navigation.
if [ -f "$CARD_ROOT/scripts/lib_app_mount.sh" ]; then
    . "$CARD_ROOT/scripts/lib_app_mount.sh"
elif [ -f "$CARD_ROOT/lib_app_mount.sh" ]; then
    . "$CARD_ROOT/lib_app_mount.sh"
else
    echo "ERROR: lib_app_mount.sh not found in $CARD_ROOT" >&2
    exit 1
fi

finish()
{
    if [ "$SYSTEM_WRITABLE" -eq 1 ]; then
        if [ -n "$SYSTEM_TEMP" ]; then
            rm -f "$SYSTEM_TEMP" 2>/dev/null || true
            SYSTEM_TEMP=
        fi
        mount -ur "$SYSTEM_MOUNT" 2>/dev/null || true
        SYSTEM_WRITABLE=0
    fi
    app_mount_finish
}

trap finish 0 1 2 15

usage()
{
    echo "Usage: $0 [--dpi NUMBER] [--debug|--no-debug]   (debug logging is off unless --debug)"
    echo "          [--no-second-sink] [--no-inject-meta] [--aap-minor N]"
    echo "          [--cluster-input]"
    echo "          [--output MODE] [--displayable N] [--log PATH]"
    echo
    echo "  Most settings come from a config FILE, which has no entry limit:"
    echo "  ClusterMap/gal_dualscreen.conf on the SD card, copied to the unit"
    echo "  by this script. Options given here are injected into the"
    echo "  environment and override the file."
    echo
    echo "  --keep-turn-by-turn  leave adi961's VCAndroidAuto.jar loaded. By"
    echo "                    default the installer removes its start-up line,"
    echo "                    because the cluster map fails when a route starts"
    echo "                    while that jar is active."
    echo "  --no-navignore    do not add the NavActiveIgnore patch when it is missing"
    echo "  --no-carplay      install the Android Auto map only, not the CarPlay map"
    echo "  --no-second-sink  register no second video service"
    echo "  --no-inject-meta  write no display_id/display_type fields"
    echo
    echo "  Bisect switches for the SERVICE_DISCOVERY_MISSING result: the"
    echo "  phone stopped answering discovery when the hook did BOTH. Run"
    echo "  each alone to find which the phone objects to."
    echo
    echo "  --aap-minor N     advertise AAP 1.N instead of the stock 1.2."
    echo "                    DHU negotiates 1.7 and gets a working cluster."
    echo "                    Risky: claims protocol this receiver does not"
    echo "                    implement. Verify Android Auto still works."
    echo
    echo "  --cluster-input   also advertise an InputSourceService for the"
    echo "                    cluster (display id 1). Proven necessary in a"
    echo "                    DHU subtractive test: removing it from a"
    echo "                    working two-display session stops the phone"
    echo "                    responding. Pair this with --aap-minor 7."
    echo
    echo "  --output MODE     what to do with the secondary sink's video:"
    echo "                      gal       forward to GAL. Reconfigures the one"
    echo "                                shared renderer and blanks the main"
    echo "                                screen. Stock path."
    echo "                      withhold  do not forward, do not decode. Frames"
    echo "                                still arrive and are counted; main"
    echo "                                screen untouched."
    echo "                      own       decode the frames ourselves into a"
    echo "                                private NvSS instance on the cluster"
    echo "                                displayable. Main screen untouched."
    echo "                      own-ack   NOT currently available for the"
    echo "                                secondary sink -- falls back to own."
    echo "                                (as own, but GAL is still told playback"
    echo "                                started, with the handler's renderer"
    echo "                                job stubbed out via a private vtable."
    echo "                    Default gal. Use own."
    echo "  --log PATH        write the hook log here. Omitted by default so"
    echo "                    the environment array stays short; the hook then"
    echo "                    uses its built-in path and falls back to"
    echo "                    /tmp/gal_dualscreen.log, which the status scripts"
    echo "                    search for anyway."
    echo "  --displayable N   cluster displayable to decode onto. Default 3;"
    echo "                    33 is the stock Kombi map window, already 800x480"
    echo "                    and already routed to the cluster by context 70."
    echo "  --no-secondary-render  alias for --output withhold. Do not forward"
    echo "                    playbackStart to GAL. GAL owns one renderer, so"
    echo "                    forwarding it blanks the main screen; withholding"
    echo "                    keeps the main screen and still counts frames."
    echo
    echo "  The cluster map window's size is read from the display manager at"
    echo "  install time. Where it is not 800x480, the phone is asked to leave"
    echo "  margins so its map has that shape, and the player fills the window."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dpi)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            DPI=$2
            shift 2
            ;;
        --aap-minor)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            AAP_MINOR=$2
            case "$AAP_MINOR" in ''|*[!0-9]*) echo "--aap-minor needs a number" >&2; exit 2 ;; esac
            shift 2
            ;;
        --cluster-input) CLUSTER_INPUT=1; shift ;;
        --no-cluster-input) CLUSTER_INPUT=0; shift ;;
        --output)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            OUTPUT="$2"
            case "$OUTPUT" in
                own-ack)
                    # Accepted rather than rejected, because the hook falls
                    # back safely and the mode becomes real once the
                    # secondary gets a proper CVideoSinkCallbackHandler.
                    # But it must not look like it is doing something.
                    echo "NOTE: own-ack is not available for the secondary sink." >&2
                    echo "      This hook writes a CVideoSinkImpl into sink+0x38, so" >&2
                    echo "      playbackStart there dispatches to that class's slot 6" >&2
                    echo "      (ackFrames), not the callback handler's playbackStart" >&2
                    echo "      that own-ack stubs. The hook will refuse the patch and" >&2
                    echo "      run as 'own'. Use --output own." >&2
                    ;;
                own)
                    # The mode's SHAPE is right -- withhold from GAL,
                    # decode ourselves, ack ourselves -- but its decoder
                    # is NvSS, and the car proved on 2026-08-22 that a
                    # second NvSS stream cannot render: it dies at
                    # NvMediaVideoMixerBindOutput because GAL owns the
                    # only physical output. Accepted rather than rejected,
                    # because it becomes correct the moment the decoder is
                    # rebuilt on NvMedia + a KD stream, and the frame
                    # extraction and acking underneath it are already
                    # right. But nobody should spend a boot on it unaware.
                    echo "NOTE: --output own cannot display anything yet." >&2
                    echo "      Its decoder is NvSS, and a second NvSS stream cannot" >&2
                    echo "      render on this unit -- it fails at" >&2
                    echo "      NvMediaVideoMixerBindOutput because GAL owns the only" >&2
                    echo "      physical output. See the NvSS experiment in README.md." >&2
                    echo "      Expect own.open to succeed, a few own.decode lines, then" >&2
                    echo "      nothing on the cluster. The useful on-car test right now" >&2
                    echo "      is ./nvmedia_probe, which needs no install and no reboot." >&2
                    ;;
                gal|withhold) ;;
                *) echo "--output must be gal, withhold, own or own-ack" >&2; exit 2 ;;
            esac
            shift 2 ;;
        --log)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            HOOK_LOG_PATH="$2"; LOG_PATH_REQUESTED=1
            shift 2 ;;
        --displayable)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            DISPLAYABLE="$2"
            case "$DISPLAYABLE" in ''|*[!0-9]*) echo "--displayable needs a number" >&2; exit 2 ;; esac
            shift 2 ;;
        --stream) STREAM=1; shift ;;
        --no-stream) STREAM=0; shift ;;
        # Documented as "alias for --output withhold", and now implemented as
        # exactly that. It used to emit GAL_DUALSCREEN_SECONDARY_RENDER=0, a key
        # the hook stopped reading when the NvSS/own-render paths were removed --
        # so the flag spent one of the ~10 environment slots to say nothing.
        --no-secondary-render) OUTPUT=withhold; shift ;;
        --no-second-sink) SECOND_SINK=0; shift ;;
        --no-inject-meta) INJECT_META=0; shift ;;
        --debug) DEBUG=1; shift ;;
        --no-debug) DEBUG=0; shift ;;
        --keep-turn-by-turn) KEEP_TBT=1; shift ;;
        --no-navignore) KEEP_NAVIGNORE=1; shift ;;
        --no-carplay) CARPLAY=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$DPI" in
    ''|*[!0-9]*) echo "DPI must be a positive integer" >&2; exit 2 ;;
esac
[ "$DPI" -gt 0 ] || { echo "DPI must be greater than zero" >&2; exit 2; }
[ -r "$CARD_ROOT/libgal_hook.so" ] || {
    echo "Missing $CARD_ROOT/libgal_hook.so" >&2
    exit 1
}
[ -r "$TARGET_CONFIG" ] || {
    echo "Missing persistent supervisor config: $TARGET_CONFIG" >&2
    exit 1
}
[ -x "$JSONLINT" ] || {
    echo "Required firmware validator is missing: $JSONLINT" >&2
    exit 1
}
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TARGET_CONFIG" || {
    echo "jsonlint could not validate the existing persistent supervisor config" >&2
    echo "No file has been modified" >&2
    exit 1
}

mkdir -p "$BACKUP_DIR" "$LOG_DIR" || {
    echo "Cannot create $BACKUP_DIR / $LOG_DIR under $CARD_ROOT" >&2
    exit 1
}
# mkdir -p SUCCEEDS on an already-existing directory even when the
# filesystem is mounted read-only, so it cannot detect the SD card's
# default state after a power cycle. Relying on it meant the install got
# as far as staging the preload, then failed on the first real write with
# "cannot create ...: Read-only file system" and reported the misleading
# "Could not locate children.gal.envs" -- pointing at the config's
# structure rather than at the mount. Probe with an actual write, which
# is the thing that has to work, and fail here with the real reason.
WRITE_PROBE="$LOG_DIR/.write_probe.$$"
if ! : > "$WRITE_PROBE" 2>/dev/null; then
    echo "Cannot write $CARD_ROOT -- it is mounted read-only." >&2
    echo "The SD card returns to read-only on every boot; run this first:" >&2
    echo "    mount -uw $CARD_ROOT" >&2
    exit 1
fi
rm -f "$WRITE_PROBE"

# Stage the preload target on the internal partition before touching the
# persistent supervisor config at all: if this fails, nothing has been
# modified yet, matching the fail-closed pattern used throughout this
# script. Always copy fresh rather than trusting an existing copy, so an
# updated libgal_hook.so on the SD card is never silently ignored.
#
# On a repeat install, PRELOAD_SO_REAL is not a fresh file -- it is the
# exact path the live LD_PRELOAD alias already resolves to, in active use
# by whatever GAL session is currently running. Stage to a temp name in
# the same directory, verify it, and only then atomically rename it onto
# the live path -- the same stage-then-atomic-rename shape used for
# TARGET_CONFIG below -- so an interrupted or partial copy (disk full,
# power loss mid-write) can never leave that live, already-relied-upon
# file half-written. A direct cp onto the live path could.
mount -uw "$APP_MOUNT" 2>/dev/null || {
    echo "Cannot remount $APP_MOUNT read-write" >&2
    exit 1
}
APP_WRITABLE=1
mkdir -p "$PRELOAD_WRITE_DIR" || {
    echo "Cannot create $PRELOAD_WRITE_DIR" >&2
    exit 1
}
# Belt-and-braces alongside the file-level chmod below: mkdir -p honors
# umask for the directory's own mode bits, and this directory needs to
# stay traversable regardless of the invoking shell's umask.
chmod 755 "$PRELOAD_WRITE_DIR" 2>/dev/null || true
PRELOAD_SO_TEMP="$PRELOAD_WRITE_DIR/libgal_hook.so.new.$$"
cp "$CARD_ROOT/libgal_hook.so" "$PRELOAD_SO_TEMP" || {
    rm -f "$PRELOAD_SO_TEMP"
    echo "Could not stage libgal_hook.so to $PRELOAD_SO_TEMP" >&2
    exit 1
}
chmod 755 "$PRELOAD_SO_TEMP" 2>/dev/null || true
# Byte-for-byte where available: a same-size but corrupted copy would pass
# a size-only check. This unit's firmware image ships neither cmp nor
# diff at all -- confirmed against the full extracted firmware tree, not
# just a PATH gap on this shell -- so probe for cmp and fall back to the
# size-only comparison this project used before cmp was assumed available,
# rather than hard-failing every install on a tool this target never had.
if command -v cmp >/dev/null 2>&1; then
    cmp -s "$CARD_ROOT/libgal_hook.so" "$PRELOAD_SO_TEMP" || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Staged libgal_hook.so does not match $CARD_ROOT/libgal_hook.so" >&2
        exit 1
    }
else
    SRC_SIZE=`wc -c < "$CARD_ROOT/libgal_hook.so"` || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Could not read size of $CARD_ROOT/libgal_hook.so" >&2
        exit 1
    }
    DST_SIZE=`wc -c < "$PRELOAD_SO_TEMP"` || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Could not read size of staged $PRELOAD_SO_TEMP" >&2
        exit 1
    }
    [ "$SRC_SIZE" -eq "$DST_SIZE" ] || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Staged libgal_hook.so size ($DST_SIZE) does not match $CARD_ROOT/libgal_hook.so ($SRC_SIZE)" >&2
        exit 1
    }
    echo "Note: cmp is not available on this unit; verified staged copy by size only."
fi
mv "$PRELOAD_SO_TEMP" "$PRELOAD_SO_REAL" || {
    rm -f "$PRELOAD_SO_TEMP"
    echo "Could not atomically install $PRELOAD_SO_REAL" >&2
    exit 1
}
# Confirm the short /eso alias actually resolves to what was just written,
# not just that the write under /mnt/app/eso succeeded -- catches a wrong
# assumption about the /eso alias before it ever reaches the persistent
# config, rather than silently deploying a dead LD_PRELOAD path.
[ -r "$PRELOAD_SO_ALIAS" ] || {
    echo "$PRELOAD_SO_ALIAS is not readable through the short alias path" >&2
    echo "Wrote to $PRELOAD_WRITE_DIR but /eso does not resolve to it as expected" >&2
    exit 1
}
# Install libdmdt_flush.so interposer to PRELOAD_WRITE_DIR and /mnt/app/eso/lib
if [ -r "$CARD_ROOT/lib/libdmdt_flush.so" ]; then
    cp "$CARD_ROOT/lib/libdmdt_flush.so" "$PRELOAD_WRITE_DIR/libdmdt_flush.so" 2>/dev/null || true
    chmod 755 "$PRELOAD_WRITE_DIR/libdmdt_flush.so" 2>/dev/null || true
    cp "$CARD_ROOT/lib/libdmdt_flush.so" "$APP_MOUNT/eso/lib/libdmdt_flush.so" 2>/dev/null || true
    chmod 755 "$APP_MOUNT/eso/lib/libdmdt_flush.so" 2>/dev/null || true
    echo "Installed dmdt flush interposer to: $PRELOAD_WRITE_DIR/libdmdt_flush.so"
fi

# Internal copy of the settings file: the hook reads the SD card first and
# falls back to this one, so the tuned values still apply without the card.
if [ -r "$CARD_ROOT/gal_dualscreen.conf" ]; then
    cp "$CARD_ROOT/gal_dualscreen.conf" "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null || true
    chmod 644 "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null || true
    echo "Installed settings copy: $PRELOAD_WRITE_DIR/gal_dualscreen.conf"
else
    echo "NOTE: no gal_dualscreen.conf beside this script; the hook will run on built-in defaults."
fi
# CLUSTERMAP_KEEP_ARROWS=1: keep the turn-arrows jar with the map, adding it
# when missing. On SEAT the two work together; on VW the map goes blank when
# a route starts.
WITH_ARROWS=0
if [ "`sed -n 's/^CLUSTERMAP_KEEP_ARROWS=\([01]\)[ 	]*$/\1/p' "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`" = 1 ]; then
    WITH_ARROWS=1; KEEP_TBT=1
fi

# The cluster map window. The cluster's encoder expects the window it shows
# to be this size; an 800x480 window on a cluster whose map window is, say,
# 1010x376 arrives as stripes (SEAT P4708, issue #4). So the player opens its
# window at the stock Kombi map window's size: Android Auto's 800x480 frame
# is drawn into it at its own shape, and CarPlay is asked for that size
# outright. dmdt gd prints one line per window: ID, type, "W x H", buffers,
# name; 33 is the stock Kombi map.
MAP_SIZE=`( cd /eso && LD_PRELOAD="$PRELOAD_WRITE_DIR/libdmdt_flush.so" \
    LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production \
    ./bin/apps/dmdt gd ) 2>/dev/null | awk '
    $1 == 33 {
        for (i = 2; i < NF; i++) if ($i == "x") { print $(i - 1) "x" $(i + 1); exit }
    }'`
MAP_W=`echo "$MAP_SIZE" | sed -n 's/^\([0-9][0-9]*\)x[0-9][0-9]*$/\1/p'`
MAP_H=`echo "$MAP_SIZE" | sed -n 's/^[0-9][0-9]*x\([0-9][0-9]*\)$/\1/p'`
if [ -n "$MAP_W" ] && [ -n "$MAP_H" ] && [ "$MAP_W" -ge 320 ] && [ "$MAP_W" -le 1920 ] && \
   [ "$MAP_H" -ge 160 ] && [ "$MAP_H" -le 1080 ]; then
    echo "Cluster map window: ${MAP_W}x${MAP_H}"
else
    MAP_W=800; MAP_H=480
    echo "Cluster map window: not reported by the display manager; using 800x480."
fi
# Android Auto's frame is always 800x480: the phone is asked to leave
# margins so the rest has the window's shape (none for an 800x480 window).
# "|| :" because expr exits 1 when the answer is 0, and this runs under set -e.
if [ `expr $MAP_W \* 480` -gt `expr $MAP_H \* 800` ]; then
    MARGIN_W=0
    MARGIN_H=`expr 480 - \( 800 \* $MAP_H + $MAP_W \) / \( 2 \* $MAP_W \) \* 2 || :`
else
    MARGIN_W=`expr 800 - \( 480 \* $MAP_W + $MAP_H \) / \( 2 \* $MAP_H \) \* 2 || :`
    MARGIN_H=0
fi
if [ "$MARGIN_W" -gt 0 ] || [ "$MARGIN_H" -gt 0 ]; then
    echo "Android Auto: 800x480 with ${MARGIN_W}x${MARGIN_H} margins, scaled to fill the window."
fi
if [ -w "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" ]; then
    { echo; echo "# Written by the installer from the cluster map window it read."
      echo "GAL_PLAYER_WINDOW=${MAP_W}x${MAP_H}"
      echo "GAL_SECONDARY_MARGINS=${MARGIN_W}x${MARGIN_H}"; } >> "$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
fi

# Install stream-player to /mnt/app/navigation
# Through a new file and a rename: copying over the old player fails while it
# runs, and would leave the old one in place.
if [ -x "$CARD_ROOT/stream-player" ]; then
    PLAYER_DST="$APP_MOUNT/navigation/stream-player"
    if cp "$CARD_ROOT/stream-player" "$PLAYER_DST.new" 2>/dev/null && \
       [ "`wc -c < $CARD_ROOT/stream-player`" = "`wc -c < $PLAYER_DST.new`" ] && \
       chmod 755 "$PLAYER_DST.new" && mv "$PLAYER_DST.new" "$PLAYER_DST"; then
        echo "Installed stream-player to: $PLAYER_DST"
    else
        rm -f "$PLAYER_DST.new"
        echo "WARNING: could not install stream-player to $PLAYER_DST; the previous player, if any, stays." >&2
    fi
fi

# The CarPlay map, when this unit's CarPlay library is the one the hook knows.
CARPLAY_WHY=
if [ "$CARPLAY" -eq 0 ]; then
    CARPLAY_WHY="not requested (--no-carplay)"
elif [ ! -r "$CARD_ROOT/carplay/libcarplay_cluster.so" ] || [ ! -r "$CARD_ROOT/carplay/carplay_cluster.sh" ]; then
    CARPLAY_WHY="its files are not in this package"
elif [ "`wc -c < $AIRPLAY_LIB 2>/dev/null | sed 's/ //g'`" != "$AIRPLAY_SIZE" ]; then
    CARPLAY_WHY="this unit's CarPlay library is a different build (`wc -c < $AIRPLAY_LIB 2>/dev/null | sed 's/ //g'` bytes)"
elif [ -d "$APP_MOUNT/carplaymaps" ] || grep -q carplaymaps "$APP_MOUNT/eso/bin/apps/dio_manager" 2>/dev/null; then
    CARPLAY_WHY="CarPlay Maps VC is installed; uninstall it first to use this one"
else
    cp "$CARD_ROOT/carplay/libcarplay_cluster.so" "$PRELOAD_WRITE_DIR/libcarplay_cluster.so.new" && \
        cp "$CARD_ROOT/carplay/carplay_cluster.sh" "$PRELOAD_WRITE_DIR/carplay_cluster.sh" && \
        [ "`wc -c < $CARD_ROOT/carplay/libcarplay_cluster.so`" = "`wc -c < $PRELOAD_WRITE_DIR/libcarplay_cluster.so.new`" ] && \
        chmod 755 "$PRELOAD_WRITE_DIR/libcarplay_cluster.so.new" "$PRELOAD_WRITE_DIR/carplay_cluster.sh" && \
        mv "$PRELOAD_WRITE_DIR/libcarplay_cluster.so.new" "$PRELOAD_WRITE_DIR/libcarplay_cluster.so" && CARPLAY_OK=1
    if [ "$CARPLAY_OK" -eq 1 ]; then
        echo "Installed the CarPlay map files to: $PRELOAD_WRITE_DIR"
    else
        rm -f "$PRELOAD_WRITE_DIR/libcarplay_cluster.so.new"
        CARPLAY_WHY="copying its files failed"
    fi
fi
[ "$CARPLAY_OK" -eq 1 ] || echo "CarPlay map: not installed, $CARPLAY_WHY."

# CarPlay's safe area: the part of the window the dials do not cover, where
# the iPhone keeps the car and its instruction card. The same
# GAL_SECONDARY_INSETS (top,bottom,left,right) Android Auto uses, which are
# in its 800x480 frame after margins, scaled to the window. harman-f's hook
# reads it when the iPhone connects. Without it the whole window counts as
# visible (Golf R: card and car under the dials).
CARPLAY_SAFEAREA=$APP_MOUNT/root/mibr-carplay111-safearea.conf
if [ "$CARPLAY_OK" -eq 1 ]; then
    INSETS=`sed -n 's/^GAL_SECONDARY_INSETS=\([0-9]*\),\([0-9]*\),\([0-9]*\),\([0-9]*\)[ 	]*$/\1 \2 \3 \4/p' \
        "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
    set -- ${INSETS:-40 40 127 127}
    SAFE_Y=`expr $1 \* $MAP_H / \( 480 - $MARGIN_H \) || :`
    SAFE_B=`expr $2 \* $MAP_H / \( 480 - $MARGIN_H \) || :`
    SAFE_X=`expr $3 \* $MAP_W / \( 800 - $MARGIN_W \) || :`
    SAFE_R=`expr $4 \* $MAP_W / \( 800 - $MARGIN_W \) || :`
    SAFE_W=`expr $MAP_W - $SAFE_X - $SAFE_R || :`
    SAFE_H=`expr $MAP_H - $SAFE_Y - $SAFE_B || :`
    if [ "$SAFE_W" -ge 160 ] && [ "$SAFE_H" -ge 120 ] &&
       printf 'x=%s\ny=%s\nw=%s\nh=%s\n' $SAFE_X $SAFE_Y $SAFE_W $SAFE_H > "$CARPLAY_SAFEAREA"; then
        echo "CarPlay map: safe area ${SAFE_W}x${SAFE_H} at ${SAFE_X},${SAFE_Y} (from the insets)"
    else
        rm -f "$CARPLAY_SAFEAREA"
        echo "CarPlay map: insets leave too little of the window; using all of it"
    fi
else
    rm -f "$CARPLAY_SAFEAREA" 2>/dev/null || true
fi

mount -ur "$APP_MOUNT" 2>/dev/null || true
APP_WRITABLE=0
echo "Installed preload target: $PRELOAD_SO_ALIAS"

TARGET_IS_HOOKED=0
if grep -q 'libgal_hook.so' "$TARGET_CONFIG" 2>/dev/null; then
    TARGET_IS_HOOKED=1
fi

# Never label an already-injected file as the original. This matters when a
# different/new SD card is inserted while the persistent hook is still active.
if [ ! -r "$ORIGINAL" ]; then
    if [ "$TARGET_IS_HOOKED" -eq 0 ]; then
        cp "$TARGET_CONFIG" "$ORIGINAL" || exit 1
    elif [ -r "$PERSISTENT_BACKUP" ] && \
         ! grep -q 'libgal_hook.so' "$PERSISTENT_BACKUP" 2>/dev/null; then
        cp "$PERSISTENT_BACKUP" "$ORIGINAL" || exit 1
    else
        echo "Active config is already injected and no untouched backup is available" >&2
        echo "Refusing to overwrite or mislabel the original firmware config" >&2
        exit 1
    fi
    echo "Saved untouched supervisor config: $ORIGINAL"
fi

if grep -q 'libgal_hook.so' "$ORIGINAL" 2>/dev/null; then
    echo "SD recovery copy is not untouched: $ORIGINAL" >&2
    exit 1
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$ORIGINAL" || {
    echo "SD recovery copy failed jsonlint: $ORIGINAL" >&2
    exit 1
}

# A repeated install is rebuilt from the first untouched backup. This avoids
# accumulating duplicate LD_PRELOAD/environment entries.
SOURCE="$TARGET_CONFIG"
if [ "$TARGET_IS_HOOKED" -eq 1 ]; then
    SOURCE="$ORIGINAL"
fi

TEMP="$CARD_ROOT/logs/smartphone_integrator.json.new.$$"

# Point the hook at the SD-card log path. The SD card is writable right
# now (this script required it), and stays writable across a GAL restart
# that does not go through a fresh boot. It mounts read-only again on the
# next boot unless something remounts it before GAL starts -- which is
# before any interactive login shell could run a .profile-based
# "mount -uw" workaround. libgal_hook.so's own hook_vlog() already
# handles that case: if opening this path fails, it falls back to
# /tmp/gal_dualscreen.log automatically. hook_status.sh and
# runtime_debug.sh both check the SD path first and fall back to /tmp the
# same way, so no separate configuration is needed here for that case.
HOOK_LOG_PATH="$LOG_DIR/gal_dualscreen.log"
# Only emit the variable when asked, so the default install is
# byte-identical to before this option existed.
#
# Emit ONLY variables that differ from their built-in defaults.
#
# smartphone_integrator silently drops entries past a limit in this
# array: with 11 entries the whole injection vanished -- GAL started with
# no LD_PRELOAD and no GAL_DUALSCREEN_* at all, keeping only the last two
# (the stock LD_LIBRARY_PATH and IPL_CONFIG_DIR_GAL), while the config on
# disk still looked correct. Nothing reports this; the hook simply never
# loads. Nine entries were fine, so keep this list as short as possible
# and never assume a new variable is free.
OPT_ENV=
# GAL_STREAM_ENABLE and GAL_DUALSCREEN_CLUSTER_INPUT both default ON inside
# the hook (environment_flag_default_on), so the OFF value is the one that has
# to be emitted -- the reverse of what these two lines used to do. Emitting the
# ON value spent a slot saying what the hook already assumed, and, far worse,
# --no-stream and --no-cluster-input emitted NOTHING and so did nothing at all:
# the hook fell back to its default and turned the feature on anyway, while the
# summary below dutifully reported it as 0.
[ "$STREAM" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_STREAM_ENABLE=0\", "
[ -n "$AAP_MINOR" ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_AAP_MINOR=$AAP_MINOR\", "
[ "$CLUSTER_INPUT" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_CLUSTER_INPUT=0\", "
[ "$SECOND_SINK" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_SECOND_SINK=0\", "
[ "$INJECT_META" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_INJECT_META=0\", "
# --output is the only knob on this axis now; --no-secondary-render folds
# into it at parse time above.
[ -n "$OUTPUT" ] && [ "$OUTPUT" != gal ] && \
    OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_OUTPUT=$OUTPUT\", "
# 3 is the hook's built-in default displayable; only send a different one.
[ -n "$DISPLAYABLE" ] && [ "$DISPLAYABLE" -ne 3 ] && \
    OPT_ENV="$OPT_ENV\"GAL_VC_DISPLAYABLE_ID=$DISPLAYABLE\", "
# 140 is the hook's built-in default, so emitting it wastes one of the few
# env slots available. Only send it when it differs -- and the two MUST
# agree: if this said 160 while the hook defaulted to 140, running without
# --dpi would emit nothing and silently apply 140 while every message here
# claimed 160. tools/verify_constants.sh checks they match.
DPI_ENV=
[ "$DPI" -ne 140 ] && DPI_ENV="\"GAL_SECONDARY_DPI=$DPI\", "
# GAL_HOOK_LOG costs one of the ~10 usable slots, and without it the hook
# uses its own compiled-in path and still falls back to /tmp when the card
# is read-only -- which it is on every boot. The status scripts search the
# built-in path too, so omitting it changes where the log lands but not
# whether the tooling finds it. Emitted only when --log asked for a path.
LOG_ENV=
[ -n "$LOG_PATH_REQUESTED" ] && LOG_ENV="\"GAL_HOOK_LOG=$HOOK_LOG_PATH\", "
INJECTION="\"LD_PRELOAD=$PRELOAD_SO_ALIAS\", \"GAL_DUALSCREEN_ENABLE=1\", \"GAL_DUALSCREEN_DEBUG=$DEBUG\", $OPT_ENV$LOG_ENV$DPI_ENV"

# Refuse to write an array that smartphone_integrator would silently
# truncate. At 11 entries the ENTIRE injection was dropped once -- GAL ran
# with no LD_PRELOAD at all while this file still looked correct on disk,
# and the only symptom was a hook that never loaded. Failing loudly here is
# worth more than one extra option.
INJECTED_COUNT=`echo "$INJECTION" | awk -F'", ' '{print NF-1}'`
EXISTING_COUNT=`awk '
BEGIN { in_children=0; in_gal=0 }
{
    if ($0 ~ /"children"[ 	]*:/) in_children=1
    if (in_children && !in_gal && $0 ~ /^[ 	]*"gal"[ 	]*:/) in_gal=1
    if (in_gal && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
        line=$0; sub(/^[^\[]*\[/, "", line); sub(/\].*$/, "", line)
        n=split(line, parts, /"[ 	]*,[ 	]*"/)
        if (line ~ /^[ 	]*$/) n=0
        print n; exit
    }
}' "$SOURCE"`
[ -n "$EXISTING_COUNT" ] || EXISTING_COUNT=0
ENTRY_COUNT=`expr $INJECTED_COUNT + $EXISTING_COUNT`
echo "Environment entries: $INJECTED_COUNT injected + $EXISTING_COUNT already in the stock config"
if [ "$ENTRY_COUNT" -gt 10 ]; then
    echo "Refusing to install: $ENTRY_COUNT environment entries." >&2
    echo "smartphone_integrator silently drops the whole array past ~10," >&2
    echo "so the hook would never load and nothing would report it." >&2
    echo "Drop an option -- the default for --dpi costs nothing." >&2
    exit 3
fi
echo "Environment entries: $ENTRY_COUNT (limit 10)"

awk -v injection="$INJECTION" '
BEGIN { in_children=0; in_gal=0; patched=0 }
{
    if ($0 ~ /"children"[ 	]*:/) in_children=1
    if (in_children && !in_gal && $0 ~ /^[ 	]*"gal"[ 	]*:/) in_gal=1
    if (in_gal && !patched && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
        sub(/\[/, "[" injection)
        patched=1
    }
    print
}
END { if (!patched) exit 3 }
' "$SOURCE" > "$TEMP" || {
    rm -f "$TEMP"
    echo "Could not locate children.gal.envs in $SOURCE" >&2
    exit 1
}

grep -q "LD_PRELOAD=$PRELOAD_SO_ALIAS" "$TEMP" || {
    rm -f "$TEMP"
    echo "Generated supervisor config failed verification" >&2
    exit 1
}

# CarPlay: the same edit, on the "carplay" child (dio_manager). Built into the
# same file because a repeated install starts again from the untouched
# original, and the uninstall puts that original back: both phones' entries
# always come and go together. CarPlay is asked for the cluster map
# window's size, read above, so its stream fills the player's window.
if [ "$CARPLAY_OK" -eq 1 ]; then
    CP_INJECTION="\"LD_PRELOAD=$CARPLAY_PRELOAD\", \"ALTSCREEN111_WIDTH=$MAP_W\", \"ALTSCREEN111_HEIGHT=$MAP_H\", "
    CP_EXISTING=`awk '
    BEGIN { in_children=0; in_cp=0 }
    {
        if ($0 ~ /"children"[ 	]*:/) in_children=1
        if (in_children && !in_cp && $0 ~ /^[ 	]*"carplay"[ 	]*:/) in_cp=1
        if (in_cp && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
            line=$0; sub(/^[^\[]*\[/, "", line); sub(/\].*$/, "", line)
            if (line ~ /LD_PRELOAD/) { print "preload"; exit }
            n=split(line, parts, /"[ 	]*,[ 	]*"/)
            if (line ~ /^[ 	]*$/) n=0
            print n; exit
        }
    }' "$SOURCE"`
    if [ "$CP_EXISTING" = preload ]; then
        CARPLAY_OK=0; CARPLAY_WHY="CarPlay already has a preloaded library (another CarPlay mod?)"
    elif [ -z "$CP_EXISTING" ]; then
        CARPLAY_OK=0; CARPLAY_WHY="no carplay entry in the supervisor config"
    elif [ `expr $CP_EXISTING + 3` -gt 10 ]; then
        CARPLAY_OK=0; CARPLAY_WHY="its environment list would pass the limit of 10"
    else
        awk -v injection="$CP_INJECTION" '
        BEGIN { in_children=0; in_cp=0; patched=0 }
        {
            if ($0 ~ /"children"[ 	]*:/) in_children=1
            if (in_children && !in_cp && $0 ~ /^[ 	]*"carplay"[ 	]*:/) in_cp=1
            if (in_cp && !patched && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
                sub(/\[/, "[" injection)
                patched=1
            }
            print
        }
        END { if (!patched) exit 3 }
        ' "$TEMP" > "$TEMP.cp" && grep -q "LD_PRELOAD=$CARPLAY_PRELOAD" "$TEMP.cp" && \
            grep -q "LD_PRELOAD=$PRELOAD_SO_ALIAS" "$TEMP.cp" && mv "$TEMP.cp" "$TEMP" || {
            rm -f "$TEMP.cp"
            CARPLAY_OK=0; CARPLAY_WHY="the carplay entry could not be edited"
        }
    fi
    if [ "$CARPLAY_OK" -eq 1 ]; then
        echo "CarPlay map: added to dio_manager's start-up ($CP_EXISTING + 3 environment entries)."
    else
        echo "CarPlay map: not installed, $CARPLAY_WHY. The Android Auto map is unaffected."
    fi
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TEMP" || {
    rm -f "$TEMP"
    echo "Generated supervisor config failed jsonlint validation" >&2
    exit 1
}

mount -uw "$SYSTEM_MOUNT" 2>/dev/null || {
    rm -f "$TEMP"
    echo "Cannot remount $SYSTEM_MOUNT read-write" >&2
    exit 1
}
SYSTEM_WRITABLE=1
cp "$TARGET_CONFIG" "$BACKUP_DIR/smartphone_integrator.json.before_enable.$$"
if [ ! -r "$PERSISTENT_BACKUP" ]; then
    RECOVERY_SOURCE=$ORIGINAL
    # On a first clean install, preserve the exact currently active firmware
    # file beside the target. Use the SD recovery only for a repeated install.
    [ "$TARGET_IS_HOOKED" -eq 1 ] || RECOVERY_SOURCE=$TARGET_CONFIG
    cp "$RECOVERY_SOURCE" "$PERSISTENT_BACKUP" || {
        echo "Could not create persistent recovery copy: $PERSISTENT_BACKUP" >&2
        exit 1
    }
fi
if grep -q 'libgal_hook.so' "$PERSISTENT_BACKUP" 2>/dev/null; then
    echo "Persistent recovery copy unexpectedly contains the hook: $PERSISTENT_BACKUP" >&2
    exit 1
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$PERSISTENT_BACKUP" || {
    echo "Persistent recovery copy failed jsonlint: $PERSISTENT_BACKUP" >&2
    exit 1
}
SYSTEM_TEMP="$TARGET_CONFIG.gal-dualscreen-new"
cp "$TEMP" "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Could not stage $SYSTEM_TEMP" >&2
    exit 1
}
chmod 644 "$SYSTEM_TEMP" 2>/dev/null || true
grep -q "LD_PRELOAD=$PRELOAD_SO_ALIAS" "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Staged supervisor config failed verification" >&2
    exit 1
}
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Staged supervisor config failed jsonlint validation" >&2
    exit 1
}
mv "$SYSTEM_TEMP" "$TARGET_CONFIG" || {
    rm -f "$TEMP"
    echo "Could not atomically install $TARGET_CONFIG" >&2
    exit 1
}
SYSTEM_TEMP=
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TARGET_CONFIG" || {
    echo "Installed config failed validation; restoring persistent original" >&2
    if cp "$PERSISTENT_BACKUP" "$TARGET_CONFIG"; then
        echo "Restored $TARGET_CONFIG from $PERSISTENT_BACKUP" >&2
    else
        echo "CRITICAL: restore from $PERSISTENT_BACKUP also failed" >&2
        echo "CRITICAL: $TARGET_CONFIG is left in a state that failed jsonlint" >&2
        echo "CRITICAL: fix this file manually before rebooting the unit" >&2
    fi
    rm -f "$TEMP"
    exit 1
}
rm -f "$TEMP"
if [ "$CARPLAY_OK" -eq 1 ]; then carplay_pf_open; else carplay_pf_close; fi
sync
mount -ur "$SYSTEM_MOUNT" 2>/dev/null || true
SYSTEM_WRITABLE=0
trap - 0 1 2 15

echo "Hook environment installed for the supervisor-owned GAL."
echo "  persistent config: $TARGET_CONFIG"
echo "  persistent recovery: $PERSISTENT_BACKUP"
echo "  preload target: $PRELOAD_SO_ALIAS"
echo "    on the internal /mnt/app partition, not the SD card -- avoids the"
echo "    SD-card mount-timing race at GAL's boot-time launch."
echo "  output mode: $OUTPUT (video forwarded to stream-player)"
echo "  cluster: Android Auto 800x480 @ 30 fps (margins ${MARGIN_W}x${MARGIN_H}), DPI $DPI, ${MAP_W}x${MAP_H} window"
if [ "$CARPLAY_OK" -eq 1 ]; then echo "  CarPlay map: installed, ${MAP_W}x${MAP_H}"; else echo "  CarPlay map: no ($CARPLAY_WHY)"; fi
echo "  debug logs: $DEBUG"
echo "  second sink: $SECOND_SINK   inject metadata: $INJECT_META"
echo "  AAP minor version: ${AAP_MINOR:-2 (stock)}"
echo "  stream forwarding: $STREAM"
echo "  cluster input service: $CLUSTER_INPUT"
echo "  hook log: $HOOK_LOG_PATH"
echo "    falls back to /tmp/gal_dualscreen.log (RAM-backed, does not survive"
echo "    a reboot) if the SD card is read-only when GAL starts -- true on"
echo "    every boot unless the SD card is remounted -uw before GAL starts."

# ---- Java interface: the two patches that decide whether the map stays up ----
# NavActiveIgnore must be loaded, and the turn-by-turn jar must not be. Both are
# single lines in the Java start-up script, edited through lsd_jar.sh, which
# checks every change before it replaces the file.
LSD_SH=/mnt/app/eso/hmi/lsd/lsd.sh
NAVIGNORE_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_navignore_added
# Firmware where the bundled NavActiveIgnore.jar has been seen working. It is a
# Java patch: on a firmware it does not fit, the centre screen may not start,
# so it is never added automatically anywhere else.
NAVIGNORE_TRAINS="MHI2_ER_VWG13_P4521 MHI2_ER_VWG13_K4525"
TRAIN=unknown
for f in /net/rcc/dev/shmem/version.txt /dev/shmem/version.txt; do
    if [ -r "$f" ]; then
        TRAIN=`grep "Current train" "$f" | sed 's/Current train = //' | sed -e 's|["'"'"']||g' | sed 's/\r//'`
        break
    fi
done
echo
if [ ! -r "$LSD_SH" ] || [ ! -r "$CARD_ROOT/lsd_jar.sh" ]; then
    echo "WARNING: cannot check the Java interface ($LSD_SH or lsd_jar.sh missing)." >&2
else
    if sh "$CARD_ROOT/lsd_jar.sh" loaded NavActiveIgnore.jar; then
        echo "Java check: NavActiveIgnore is loaded (required)."
    elif sh "$CARD_ROOT/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then
        # CarPlay Maps VC ships the same nine classes under another name.
        echo "Java check: CarPlayNavigationPatch is loaded (the same patch as NavActiveIgnore)."
    elif [ "$KEEP_NAVIGNORE" -eq 1 ]; then
        echo "Java check: NavActiveIgnore is NOT loaded and was left alone (--no-navignore)."
        echo "            The cluster will drop its map when the phone navigates."
    else
        NAV_OK=0
        for t in $NAVIGNORE_TRAINS; do case "$TRAIN" in *${t}*) NAV_OK=1 ;; esac; done
        if [ "$NAV_OK" -eq 1 ]; then
            echo "Java check: NavActiveIgnore is not loaded; adding it (firmware $TRAIN)."
            if sh "$CARD_ROOT/lsd_jar.sh" add NavActiveIgnore.jar "$CARD_ROOT/thirdparty/NavActiveIgnore.jar"; then
                mount -uw /mnt/app 2>/dev/null && { : > "$NAVIGNORE_MARKER"; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not add NavActiveIgnore; lsd.sh is unchanged." >&2
                echo "         Apply it from the toolbox: Customization > Navigation." >&2
            fi
        else
            echo "WARNING: NavActiveIgnore is NOT loaded, and it is not added automatically" >&2
            echo "         on firmware $TRAIN. Apply it from the toolbox:" >&2
            echo "         Customization > Navigation > Ignore navigation-active status." >&2
        fi
    fi
    TBT_OK=0
    for t in `sed -n 's/^TBT_TRAINS="\(.*\)"/\1/p' "$CARD_ROOT/GEM/common.sh" 2>/dev/null`; do
        case "$TRAIN" in *${t}*) TBT_OK=1 ;; esac
    done
    if [ "$WITH_ARROWS" -eq 1 ] && ! sh "$CARD_ROOT/lsd_jar.sh" loaded VCAndroidAuto.jar; then
        if [ "$TBT_OK" -eq 1 ]; then
            echo "Java check: adding VCAndroidAuto.jar beside the map (CLUSTERMAP_KEEP_ARROWS=1)."
            if sh "$CARD_ROOT/lsd_jar.sh" add VCAndroidAuto.jar "$CARD_ROOT/thirdparty/VCAndroidAuto.jar"; then
                mount -uw /mnt/app 2>/dev/null && { : > /mnt/app/eso/hmi/lsd/.aacluster_tbt_added; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not add VCAndroidAuto.jar; lsd.sh is unchanged." >&2
            fi
        else
            echo "WARNING: CLUSTERMAP_KEEP_ARROWS=1 ignored: the arrows jar is not known to" >&2
            echo "         work on firmware $TRAIN." >&2
        fi
    fi
    if sh "$CARD_ROOT/lsd_jar.sh" loaded VCAndroidAuto.jar; then
        if [ "$KEEP_TBT" -eq 1 ]; then
            echo "Java check: VCAndroidAuto.jar is loaded and was kept with the map."
            case "$TRAIN" in
                *_VWG*) echo "            On VW, expect the cluster map to go blank when a route starts." ;;
            esac
        elif sh "$CARD_ROOT/turn_by_turn.sh" remove; then
            :
        else
            echo "WARNING: could not remove the VCAndroidAuto.jar line; lsd.sh is unchanged." >&2
            echo "         The hook is installed, but the map may fail when a route starts." >&2
        fi
    else
        echo "Java check: VCAndroidAuto.jar is not loaded (good)."
    fi
fi

echo
echo "Reboot the unit to apply it. Do not start a second GAL manually."
