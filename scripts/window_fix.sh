#!/bin/sh
# Started by the player when the cockpit's map window is not the size in the
# settings: window_fix.sh WIDTH HEIGHT. Corrects the installed settings, so the
# phone is asked for the right shape from the next start. It only changes
# the two values the installer wrote.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:$PATH
export PATH
W=$1
H=$2
case "$W$H" in ''|*[!0-9]*) exit 2 ;; esac
CONF=/mnt/app/eso/lib/gal_dualscreen/gal_dualscreen.conf
[ -w "$CONF" ] || mount -uw /mnt/app 2>/dev/null
# As in enable_hook.sh: margins leave the window's shape in the 800x480 frame.
if [ `expr $W \* 480` -gt `expr $H \* 800` ]; then
    MARGIN_W=0
    MARGIN_H=`expr 480 - \( 800 \* $H + $W \) / \( 2 \* $W \) \* 2`
else
    MARGIN_W=`expr 800 - \( 480 \* $W + $H \) / \( 2 \* $H \) \* 2`
    MARGIN_H=0
fi
sed -e "s/^GAL_PLAYER_WINDOW=.*/GAL_PLAYER_WINDOW=${W}x${H}/" \
    -e "s/^GAL_SECONDARY_MARGINS=.*/GAL_SECONDARY_MARGINS=${MARGIN_W}x${MARGIN_H}/" \
    "$CONF" > "$CONF.new" && mv "$CONF.new" "$CONF"
RC=$?
mount -ur /mnt/app 2>/dev/null
echo "window_fix: ${W}x${H} margins ${MARGIN_W}x${MARGIN_H} rc=$RC" >> /tmp/stream-player.log
exit $RC
