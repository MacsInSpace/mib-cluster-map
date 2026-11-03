# Shared by enable_hook.sh and the green menu's sharper-map switch
# (full_frame.sh): how Android Auto's frame is fitted to the cluster map
# window, and the lines of the unit's settings copy that say so.
# From AMDFX60's fork (GPL-3.0), reported car-tested on a Skoda Superb.
#
# Android Auto's frame is always 800x480. Where the window has another
# shape, the phone is asked to leave margins so the rest (the band) has the
# window's shape, 0x182 on 1010x376, and the player scales the band to the
# window. Full frame (CLUSTERMAP_FULL_FRAME=1) asks for no margins and
# declares non-square pixels instead, pixel_aspect_ratio_e4 = 6000 * W / H
# (16117 on 1010x376): the phone draws on all 480 lines, squeezed, and the
# player stretches the frame to the window.

# frame_full_ok W H
# True when full frame can apply: only on windows wider than the frame's 5:3.
# On 5:3 every line carries map already, and on a narrower window the hook
# keeps DPI and insets as they are (src/gal_hook.c).
frame_full_ok()
{
    [ `expr $1 \* 480` -gt `expr $2 \* 800` ]
}

# frame_geometry W H FULL
# Sets BAND_MARGIN_W/H (the margins of the band, whatever FULL says: the
# insets are measured in it) and MARGIN_W/H and PIXEL_ASPECT_E4 for FULL.
# FULL=1 on a window that is not wider than 5:3 gives the margins, as 0 does;
# CLUSTERMAP_FULL_FRAME is still written as asked, so a later correction of
# the window (window_fix.sh) can apply it.
# "|| :" because expr exits 1 when the answer is 0, and callers run under
# set -e.
frame_geometry()
{
    if [ `expr $1 \* 480` -gt `expr $2 \* 800` ]; then
        BAND_MARGIN_W=0
        BAND_MARGIN_H=`expr 480 - \( 800 \* $2 + $1 \) / \( 2 \* $1 \) \* 2 || :`
    else
        BAND_MARGIN_W=`expr 800 - \( 480 \* $1 + $2 \) / \( 2 \* $2 \) \* 2 || :`
        BAND_MARGIN_H=0
    fi
    if [ "$3" = 1 ] && frame_full_ok $1 $2; then
        MARGIN_W=0
        MARGIN_H=0
        PIXEL_ASPECT_E4=`expr \( 6000 \* $1 + $2 / 2 \) / $2`
    else
        MARGIN_W=$BAND_MARGIN_W
        MARGIN_H=$BAND_MARGIN_H
        PIXEL_ASPECT_E4=10000
    fi
}

FRAME_CONF_MARK="# Cluster map window (written by the installer, switched by the green menu)"

# frame_write_conf CONF W H FULL
# Replaces the window lines in CONF with those for a W x H window and FULL
# (0 or 1), through a new file and a rename; returns 1 with CONF untouched
# if that fails. Every existing line of these keys goes first: the hook takes
# a key's first line and the player its last, so each must be there once.
frame_write_conf()
{
    frame_geometry "$2" "$3" "$4"
    sed -e '/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_MARGINS[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4[ 	]*=/d' \
        -e '/^[ 	]*CLUSTERMAP_FULL_FRAME[ 	]*=/d' \
        -e '/^# Cluster map window (written by the installer/d' \
        -e '/^# Written by the installer from the cluster map window it read\.$/d' \
        "$1" > "$1.new" 2>/dev/null &&
    { echo
      echo "$FRAME_CONF_MARK"
      echo "GAL_PLAYER_WINDOW=$2x$3"
      echo "GAL_SECONDARY_MARGINS=${MARGIN_W}x${MARGIN_H}"
      echo "GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4=$PIXEL_ASPECT_E4"
      echo "CLUSTERMAP_FULL_FRAME=$4"; } >> "$1.new" 2>/dev/null &&
    mv "$1.new" "$1" 2>/dev/null || { rm -f "$1.new" 2>/dev/null; return 1; }
    chmod 644 "$1" 2>/dev/null
    return 0
}
