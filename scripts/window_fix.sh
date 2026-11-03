#!/bin/sh
# Started by the player when the cockpit's map window is not the size in the
# settings: window_fix.sh WIDTH HEIGHT. Corrects the installed settings, so the
# phone is asked for the right shape from the next start. It only changes
# the window lines the installer wrote, through lib_cluster_frame.sh, which
# the installer copies next to this script.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:$PATH
export PATH
W=$1
H=$2
case "$W$H" in ''|*[!0-9]*) exit 2 ;; esac
LOG=/tmp/stream-player.log
LIB="`dirname "$0"`/lib_cluster_frame.sh"
if [ ! -r "$LIB" ]; then
    echo "window_fix: ${W}x${H} not written: $LIB missing (install again)" >> $LOG
    exit 1
fi
. "$LIB"
CONF=/mnt/app/eso/lib/gal_dualscreen/gal_dualscreen.conf
FULL=`sed -n 's/^CLUSTERMAP_FULL_FRAME=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$FULL" = 1 ] || FULL=0
[ -w "$CONF" ] || mount -uw /mnt/app 2>/dev/null
frame_write_conf "$CONF" $W $H $FULL
RC=$?
mount -ur /mnt/app 2>/dev/null
echo "window_fix: ${W}x${H} margins ${MARGIN_W}x${MARGIN_H} pixel_aspect_e4 ${PIXEL_ASPECT_E4} rc=$RC" >> $LOG
exit $RC
