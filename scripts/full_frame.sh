#!/bin/sh
# The green menu's picture switch writes the selected Android Auto frame mode
# into the unit's settings copy. It takes effect at the next reboot.
# The green menu's sharper-map switch: CLUSTERMAP_FULL_FRAME on or off in the
# unit's own copy of the settings, so it can be tried in the car without
# editing the card and installing again. Changes only the window lines of
# that copy (lib_cluster_frame.sh); takes effect at the next reboot: gal
# reads the settings once at its start and hands the same frame values to
# every player it starts until then. An install from the card writes the
# card's setting again.
# From AMDFX60's fork (GPL-3.0).
#
#   full_frame.sh on|off|720p|1080p
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
. "$HERE/lib_cluster_frame.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"

case "$1" in
    on)     WANT=1; WANT_720=0; WANT_1080=0 ;;
    off)    WANT=0; WANT_720=0; WANT_1080=0 ;;
    720p)   WANT=; WANT_720=1; WANT_1080=0 ;;
    1080p)  WANT=; WANT_720=0; WANT_1080=1 ;;
    *)      echo "usage: $0 on|off|720p|1080p" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
WINDOW=`sed -n 's/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=[ 	]*\([0-9][0-9]*x[0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
MAP_W=`echo "$WINDOW" | sed -n 's/^\([0-9]*\)x[0-9]*$/\1/p'`
MAP_H=`echo "$WINDOW" | sed -n 's/^[0-9]*x\([0-9]*\)$/\1/p'`
if [ -z "$MAP_W" ] || [ -z "$MAP_H" ] || [ "$MAP_W" -lt 320 ] || [ "$MAP_W" -gt 1920 ] ||
   [ "$MAP_H" -lt 160 ] || [ "$MAP_H" -gt 1080 ]; then
    echo "The settings copy names no cluster map window. Install again from the"
    echo "card (with the cockpit in map view), then use this switch."
    exit 1
fi
# Written only by an installer that has the full-frame hook and player; an
# older install would take the settings and draw a squeezed map.
if ! grep -q "^$FRAME_CONF_MARK\$" "$CONF" 2>/dev/null; then
    echo "The cluster map on the unit was installed by an older release, which"
    echo "cannot draw the sharper map. Choose \"Install cluster map\" from this"
    echo "card first, then use this switch. Nothing changed."
    exit 1
fi
if [ "$WANT" = 1 ] && ! frame_full_ok "$MAP_W" "$MAP_H"; then
    echo "The cluster map window is ${MAP_W}x${MAP_H}, not wider than Android Auto's"
    echo "5:3 frame: the map already uses every line, so there is nothing to switch."
    exit 3
fi
if [ "$WANT_720" = 1 ] && ! grep -q '^CLUSTERMAP_720P=' "$CONF" 2>/dev/null; then
    echo "The installed cluster map does not support the 720p picture. Install again from"
    echo "the card first. Nothing changed."
    exit 1
fi
if [ "$WANT_1080" = 1 ] && ! grep -q '^CLUSTERMAP_1080P=' "$CONF" 2>/dev/null; then
    echo "The installed cluster map does not support the 1080p picture. Install again from"
    echo "the card first. Nothing changed."
    exit 1
fi
# 1080p in software runs at about 15 pictures a second (Golf, #125).
if [ "$WANT_1080" = 1 ] && [ "`sed -n 's/^GAL_PLAYER_DECODER=\([a-z]*\)[ 	]*$/\1/p' "$CONF" | tail -1`" != hw ]; then
    echo "The 1080p picture needs the hardware decoder: switch it on first"
    echo "(ClusterMapOptions > Hardware decoder ON). Nothing changed."
    exit 3
fi
if [ "$WANT_720" = 1 ] && ! frame_hd_ok "$MAP_W" "$MAP_H" 1280 720; then
    echo "The cluster map window is ${MAP_W}x${MAP_H}: a 720p picture only helps on a window"
    echo "larger than 800x480 that fits in 1280x720. Nothing changed."
    exit 3
fi
if [ "$WANT_1080" = 1 ] && ! frame_hd_ok "$MAP_W" "$MAP_H" 1920 1080; then
    echo "The cluster map window is ${MAP_W}x${MAP_H}: a 1080p picture only helps on a window"
    echo "larger than 800x480 that fits in 1920x1080. Nothing changed."
    exit 3
fi

NOW=`sed -n 's/^CLUSTERMAP_FULL_FRAME=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$NOW" = 1 ] || NOW=0
NOW_720=`sed -n 's/^CLUSTERMAP_720P=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$NOW_720" = 1 ] || NOW_720=0
NOW_1080=`sed -n 's/^CLUSTERMAP_1080P=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$NOW_1080" = 1 ] || NOW_1080=0
if [ -z "$WANT" ]; then WANT=$NOW; fi
if [ "$NOW" = "$WANT" ] && [ "$NOW_720" = "$WANT_720" ] &&
   [ "$NOW_1080" = "$WANT_1080" ]; then
    case "$1" in
        720p) echo "The 720p picture is already on. Nothing changed." ;;
        1080p) echo "The 1080p picture is already on. Nothing changed." ;;
        *) echo "Sharper map is already $1. Nothing changed." ;;
    esac
    exit 3
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
if ! frame_write_conf "$CONF" "$MAP_W" "$MAP_H" "$WANT" "$WANT_720" "$WANT_1080"; then
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
if [ "$WANT_720" = 1 ] || [ "$WANT_1080" = 1 ]; then
    echo "${FRAME_MODE} picture: ON (test)."
    echo "Android Auto is asked for a ${FRAME_W}x${FRAME_H} frame with ${MARGIN_W}x${MARGIN_H} margins,"
    echo "leaving the ${MAP_W}x${MAP_H} cockpit window to show 1:1."
    echo "If the cockpit shows no map after reboot, choose Sharper map ON."
elif [ "$WANT" = 1 ]; then
    echo "Sharper map: ON."
    echo "Android Auto now draws on the whole 800x480 frame, pixel aspect"
    echo "${PIXEL_ASPECT_E4}/10000, stretched to the ${MAP_W}x${MAP_H} window. The hook"
    echo "scales DPI and insets by the same ratio, so the map should keep its"
    echo "scale and the turn card its place. Compare with OFF after a reboot."
else
    echo "Sharper map: OFF."
    echo "Back to ${MARGIN_W}x${MARGIN_H} margins."
fi
echo "Hold the power button for 10 seconds to reboot the unit."
exit 0
