#!/bin/sh

# A non-interactive shell -- ssh "host command", or anything not started
# from a login shell -- does not inherit the firmware's PATH, so dirname,
# wc, grep and the unit's own binaries are simply absent and this script
# fails in confusing ways partway through. Set it before any external
# command runs, including the dirname below.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

# dmdt links libdmdt_core.so from /eso/lib. Without this it dies with
# "ldd:FATAL: Could not load library libdmdt_core.so" -- and because the
# dmdt calls below are best-effort, that failure is otherwise silent.
LD_LIBRARY_PATH=/proc/boot:/lib:/lib/dll:/usr/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib:/eso/lib:/mnt/app/eso/lib
export LD_LIBRARY_PATH

set -eu

CARD_ROOT=`cd "\`dirname "$0"\`" && pwd`
SYSTEM_MOUNT=/mnt/system
TARGET_CONFIG=$SYSTEM_MOUNT/etc/eso/production/smartphone_integrator.json
PERSISTENT_BACKUP=$TARGET_CONFIG.gal-dualscreen.original
ORIGINAL="$CARD_ROOT/backups/smartphone_integrator.json.original"
JSONLINT=/mnt/app/eso/bin/jsonlint
VALIDATOR_LD_LIBRARY_PATH=/proc/boot:/lib:/lib/dll:/usr/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib:/eso/lib:/mnt/app/eso/lib
SYSTEM_WRITABLE=0
SYSTEM_TEMP=
# See lib_app_mount.sh (shared with enable_hook.sh) for the path
# constants and why /eso/lib was chosen over /navigation.
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

[ -r "$ORIGINAL" ] || [ -r "$PERSISTENT_BACKUP" ] || {
    echo "Missing both recovery copies: $ORIGINAL and $PERSISTENT_BACKUP" >&2
    exit 1
}
[ -x "$JSONLINT" ] || {
    echo "Required firmware validator is missing: $JSONLINT" >&2
    exit 1
}

# Prefer the same-filesystem recovery copy. Fall back to SD only if it is
# absent, and never restore a file that still contains our preload entry.
RESTORE_SOURCE=$PERSISTENT_BACKUP
[ -r "$RESTORE_SOURCE" ] || RESTORE_SOURCE=$ORIGINAL
if grep -q 'libgal_hook.so' "$RESTORE_SOURCE" 2>/dev/null; then
    echo "Recovery copy contains the hook and will not be restored: $RESTORE_SOURCE" >&2
    exit 1
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$RESTORE_SOURCE" || {
    echo "Recovery copy failed jsonlint: $RESTORE_SOURCE" >&2
    exit 1
}
mount -uw "$SYSTEM_MOUNT" 2>/dev/null || {
    echo "Cannot remount $SYSTEM_MOUNT read-write" >&2
    exit 1
}
SYSTEM_WRITABLE=1
SYSTEM_TEMP="$TARGET_CONFIG.gal-dualscreen-restore"
cp "$RESTORE_SOURCE" "$SYSTEM_TEMP" || {
    echo "Could not stage restore file: $SYSTEM_TEMP" >&2
    exit 1
}
chmod 644 "$SYSTEM_TEMP" 2>/dev/null || true
mv "$SYSTEM_TEMP" "$TARGET_CONFIG" || {
    echo "Could not atomically restore $TARGET_CONFIG" >&2
    exit 1
}
SYSTEM_TEMP=

# Track whether the route restore actually happened. These are
# best-effort by design (the config restore above is the part that
# matters, and it is already done), but reporting success when dmdt
# never ran would be actively misleading during a real recovery -- an
# observed failure mode: without LD_LIBRARY_PATH set, dmdt dies with
# "ldd:FATAL: Could not load library libdmdt_core.so" and this block
# silently did nothing while still printing success.
# The VC's display id for dmdt sc/sb is 4, NOT the 1 that `dmdt gs`
# prints as its index. dmdt accepts the wrong id and does nothing, so a
# restore issued with 1 leaves the cockpit wherever the test left it --
# during a real recovery, which is the worst time to find out.
# Confirmed by VcMOSTRenderMqb's stream player (dc 70 3 / sc 4 70,
# restoring with dc 70 33 / sc 4 70) and by on-car notes.
VC_ROUTE_RESTORED=0
if [ -x /eso/bin/apps/dmdt ]; then
    if (cd /eso && IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt dc 70 33) &&
       (cd /eso && IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt sc 4 70); then
        VC_ROUTE_RESTORED=1
    fi
fi
sync
mount -ur "$SYSTEM_MOUNT" 2>/dev/null || true
SYSTEM_WRITABLE=0
if [ "$VC_ROUTE_RESTORED" -eq 1 ]; then
    echo "Original persistent smartphone_integrator.json restored and VC route set to stock displayable 33."
else
    echo "Original persistent smartphone_integrator.json restored."
    echo "  WARNING: could not set the VC route back to stock displayable 33 via dmdt." >&2
    echo "  If the cockpit was switched to displayable 3, restore it manually with:" >&2
    echo "    cd /eso && IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt dc 70 33" >&2
    echo "    cd /eso && IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt sc 4 70" >&2
fi
echo "  restored from: $RESTORE_SOURCE"

# Best-effort cleanup of the preload copy enable_hook.sh placed under
# /mnt/app/eso/lib. The critical restore above is already complete and
# reported; a failure here is not fatal, just untidy, since the config no
# longer references it either way. Left under the same trap as the
# critical section above so an interrupt here still remounts /mnt/app
# back read-only rather than leaving it writable.
#
# Existence check happens before remounting, not after: /mnt/app is
# readable regardless of its rw/ro state, so there is no reason to open a
# writable window on the internal system partition on a run that has
# nothing to clean up (a disable without a prior enable, or a second
# disable in a row).
if [ -d "$PRELOAD_WRITE_DIR" ] || [ -f "$APP_MOUNT/eso/lib/libdmdt_flush.so" ] ||
   [ -f "$APP_MOUNT/navigation/stream-player" ]; then
    if mount -uw "$APP_MOUNT" 2>/dev/null; then
        APP_WRITABLE=1
        rm -f "$APP_MOUNT/eso/lib/libdmdt_flush.so" 2>/dev/null || true
        # enable_hook.sh put the player here; nothing else on the unit uses it.
        if rm -f "$APP_MOUNT/navigation/stream-player" 2>/dev/null; then
            echo "  removed player: $APP_MOUNT/navigation/stream-player"
        fi
        if [ -d "$PRELOAD_WRITE_DIR" ]; then
            if rm -rf "$PRELOAD_WRITE_DIR" 2>/dev/null; then
                echo "  removed preload copy: $PRELOAD_WRITE_DIR"
            else
                echo "  warning: could not remove $PRELOAD_WRITE_DIR (harmless, unreferenced)" >&2
            fi
        fi
        mount -ur "$APP_MOUNT" 2>/dev/null || true
        APP_WRITABLE=0
    else
        echo "  warning: could not remount $APP_MOUNT to clean up $PRELOAD_WRITE_DIR (harmless, unreferenced)" >&2
    fi
fi
trap - 0 1 2 15

if [ -r /mnt/app/eso/hmi/lsd/lsd.sh.before_tbt_remove ]; then
    echo
    echo "Note: the installer removed the VCAndroidAuto.jar (turn-by-turn) start-up line."
    echo "      It is NOT put back automatically. To restore it:"
    echo "        sh $CARD_ROOT/remove_turn_by_turn_jar.sh --restore"
fi
echo "Reboot the unit to run GAL without the hook."
