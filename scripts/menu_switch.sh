#!/bin/sh
# The green menu's on/off switches: one setting changed in the unit's own copy
# of the settings, so it can be tried in the car without editing the card and
# installing again. The choice is also written to the owner's saved lines, so
# the next install from a card keeps it unless the card's file says otherwise.
#
#   menu_switch.sh KEY VALUE WHEN "what it is, as a sentence"
# WHEN: phone  = read by the player, counts from the next phone connection
#       reboot = read by gal at its start, counts after a reboot
# Exit 0: switched. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
OWNER="$PRELOAD_WRITE_DIR/gal_dualscreen.owner.conf"
KEY=${1:-}
VAL=${2:-}
WHEN=${3:-}
WHAT=${4:-$KEY=$VAL}

# Only the settings that need nothing but their line changed. Anything that
# adds or removes files on the unit belongs to the installer.
case "$KEY=$VAL" in
    GAL_PLAYER_DECODER=hw|GAL_PLAYER_DECODER=sw) ;;
    GAL_PLAYER_REASSERT=0|GAL_PLAYER_REASSERT=1) ;;
    GAL_PLAYER_STATS=0|GAL_PLAYER_STATS=1) ;;
    GAL_DUALSCREEN_ENABLE=0|GAL_DUALSCREEN_ENABLE=1) ;;
    GAL_SECONDARY_UI_THEME=0|GAL_SECONDARY_UI_THEME=1|GAL_SECONDARY_UI_THEME=2) ;;
    *) echo "usage: $0 KEY VALUE phone|reboot \"what\"" >&2; exit 2 ;;
esac
case "$WHEN" in
    phone|reboot) ;;
    *) echo "usage: $0 KEY VALUE phone|reboot \"what\"" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
NOW=`sed -n "s/^[ 	]*$KEY[ 	]*=[ 	]*\([^ 	]*\)[ 	]*\$/\1/p" "$CONF" | sed -n '1p'`
if [ "$NOW" = "$VAL" ]; then
    echo "$WHAT: already set. Nothing changed."
    exit 3
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15

# Every active line of the key goes, one new line is added: the hook and the
# player both take the first line they find.
set_line()
{
    if [ -f "$1" ]; then
        sed "/^[ 	]*$KEY[ 	]*=/d" "$1" > "$1.new" 2>/dev/null || { rm -f "$1.new"; return 1; }
    else
        : > "$1.new" 2>/dev/null || return 1
    fi
    echo "$KEY=$VAL" >> "$1.new" || { rm -f "$1.new"; return 1; }
    grep "^$KEY=$VAL\$" "$1.new" >/dev/null 2>&1 || { rm -f "$1.new"; return 1; }
    mv "$1.new" "$1" 2>/dev/null || { rm -f "$1.new"; return 1; }
    chmod 644 "$1" 2>/dev/null
    return 0
}
if ! set_line "$CONF"; then
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
set_line "$OWNER" || echo "Note: the choice could not be saved for the next install; it holds until then."
sync
echo "$WHAT."
if [ "$WHEN" = reboot ]; then
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "Reconnect the phone: unplug it and plug it in again."
fi
exit 0
