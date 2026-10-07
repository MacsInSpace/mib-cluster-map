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
DEBUG=1
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
    echo "Usage: $0 [--dpi NUMBER] [--debug|--no-debug]"
    echo "          [--no-second-sink] [--no-inject-meta] [--aap-minor N]"
    echo "          [--cluster-input] [--margins WxH]"
    echo "          [--output MODE] [--displayable N] [--log PATH]"
    echo
    echo "  Most settings can also come from a config FILE, which has no"
    echo "  entry limit and can be edited between boots without re-running"
    echo "  this script: copy gal_dualscreen.conf.example to the SD card"
    echo "  root as gal_dualscreen.conf. Options given here are injected"
    echo "  into the environment and override the file."
    echo
    echo "  --keep-turn-by-turn  leave adi961's VCAndroidAuto.jar loaded. By"
    echo "                    default the installer removes its start-up line,"
    echo "                    because the cluster map fails when a route starts"
    echo "                    while that jar is active."
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
    echo "  --margins WxH     cluster margins; default 0x0, i.e. none."
    echo "                    Margins tell the phone how much of the coded"
    echo "                    800x480 frame the head unit will crop, so it"
    echo "                    keeps its interface inside the rest. The stock"
    echo "                    VW cluster reserves 400x80, leaving a 400x400"
    echo "                    visible area at offset (200,40). own mode"
    echo "                    presents the whole frame itself and crops"
    echo "                    nothing, so reserving margins would only shrink"
    echo "                    the phone's canvas for no reason."
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

# Install stream-player to /mnt/app/navigation
if [ -x "$CARD_ROOT/stream-player" ]; then
    cp "$CARD_ROOT/stream-player" "$APP_MOUNT/navigation/stream-player" 2>/dev/null || true
    chmod 755 "$APP_MOUNT/navigation/stream-player" 2>/dev/null || true
    echo "Installed stream-player to: $APP_MOUNT/navigation/stream-player"
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
echo "  cluster: 800x480 @ 30 fps, DPI $DPI"
echo "  debug logs: $DEBUG"
echo "  second sink: $SECOND_SINK   inject metadata: $INJECT_META"
echo "  AAP minor version: ${AAP_MINOR:-2 (stock)}"
echo "  stream forwarding: $STREAM"
echo "  cluster input service: $CLUSTER_INPUT"
echo "  hook log: $HOOK_LOG_PATH"
echo "    falls back to /tmp/gal_dualscreen.log (RAM-backed, does not survive"
echo "    a reboot) if the SD card is read-only when GAL starts -- true on"
echo "    every boot unless the SD card is remounted -uw before GAL starts."

# ---- Java interface checks ------------------------------------------------
# Both live in the Java start-up script, not in anything installed above.
LSD_SH=/mnt/app/eso/hmi/lsd/lsd.sh
echo
if [ -r "$LSD_SH" ]; then
    if grep -q 'NavActiveIgnore.jar' "$LSD_SH"; then
        echo "Java check: NavActiveIgnore is loaded (required)."
    else
        echo "WARNING: NavActiveIgnore is NOT loaded by $LSD_SH." >&2
        echo "         Without it the cluster drops its map when the phone navigates." >&2
        echo "         Install it from the toolbox green menu, then reboot." >&2
    fi
    if grep -q 'VCAndroidAuto.jar' "$LSD_SH"; then
        if [ "$KEEP_TBT" -eq 1 ]; then
            echo "Java check: VCAndroidAuto.jar is loaded and was kept (--keep-turn-by-turn)."
            echo "            Expect the cluster map to fail when a route starts."
        elif [ -r "$CARD_ROOT/remove_turn_by_turn_jar.sh" ]; then
            echo "Java check: VCAndroidAuto.jar is loaded; removing its start-up line."
            if sh "$CARD_ROOT/remove_turn_by_turn_jar.sh"; then
                :
            else
                echo "WARNING: could not remove the VCAndroidAuto.jar line; lsd.sh is unchanged." >&2
                echo "         The hook is installed, but the map may fail when a route starts." >&2
            fi
        else
            echo "WARNING: VCAndroidAuto.jar is loaded and remove_turn_by_turn_jar.sh is" >&2
            echo "         not beside this script. The map may fail when a route starts." >&2
        fi
    else
        echo "Java check: VCAndroidAuto.jar is not loaded (good)."
    fi
else
    echo "WARNING: cannot read $LSD_SH; Java interface checks skipped." >&2
fi

echo
echo "Reboot the unit to apply it. Do not start a second GAL manually."
