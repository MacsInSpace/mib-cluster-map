# Shared by enable_hook.sh and the green menu's picture switch
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
# Standard 800x480 geometry retains even margins. Optional 720p/1080p modes
# use asymmetric margins when needed to preserve every cockpit pixel.

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

# frame_hd_ok W H FRAME_W FRAME_H
frame_hd_ok()
{
    [ "$1" -ge 320 ] && [ "$1" -le "$3" ] &&
        [ "$2" -ge 160 ] && [ "$2" -le "$4" ]
}

# frame_geometry W H FULL [HD720] [HD1080]
# Sets the band margins, selected frame size, output margins, and pixel
# aspect ratio. High-resolution modes take precedence over full frame.
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
    FRAME_W=800
    FRAME_H=480
    FRAME_MODE=800x480
    if [ "${5:-0}" = 1 ] && frame_hd_ok "$1" "$2" 1920 1080; then
        FRAME_W=1920
        FRAME_H=1080
        FRAME_MODE=1080p
        MARGIN_W=`expr 1920 - $1 || :`
        MARGIN_H=`expr 1080 - $2 || :`
        PIXEL_ASPECT_E4=10000
    elif [ "${4:-0}" = 1 ] && frame_hd_ok "$1" "$2" 1280 720; then
        FRAME_W=1280
        FRAME_H=720
        FRAME_MODE=720p
        MARGIN_W=`expr 1280 - $1 || :`
        MARGIN_H=`expr 720 - $2 || :`
        PIXEL_ASPECT_E4=10000
    elif [ "$3" = 1 ] && frame_full_ok "$1" "$2"; then
        MARGIN_W=0
        MARGIN_H=0
        FRAME_MODE=full-frame
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
# frame_write_conf CONF W H FULL [HD720] [HD1080]
# Replaces the frame and window settings atomically.
frame_write_conf()
{
    HD720=${5:-0}
    HD1080=${6:-0}
    if [ "$HD1080" = 1 ]; then HD720=0; fi
    if [ "$HD1080" = 1 ] && ! frame_hd_ok "$2" "$3" 1920 1080; then HD1080=0; fi
    if [ "$HD720" = 1 ] && ! frame_hd_ok "$2" "$3" 1280 720; then HD720=0; fi
    frame_geometry "$2" "$3" "$4" "$HD720" "$HD1080"
    sed -e '/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_WIDTH[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_HEIGHT[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_MARGINS[ 	]*=/d' \
        -e '/^[ 	]*GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4[ 	]*=/d' \
        -e '/^[ 	]*CLUSTERMAP_FULL_FRAME[ 	]*=/d' \
        -e '/^[ 	]*CLUSTERMAP_720P[ 	]*=/d' \
        -e '/^[ 	]*CLUSTERMAP_1080P[ 	]*=/d' \
        -e '/^# Cluster map window (written by the installer/d' \
        -e '/^# Written by the installer from the cluster map window it read\.$/d' \
        "$1" > "$1.new" 2>/dev/null &&
    { echo
      echo "$FRAME_CONF_MARK"
      echo "GAL_PLAYER_WINDOW=$2x$3"
      echo "GAL_SECONDARY_WIDTH=$FRAME_W"
      echo "GAL_SECONDARY_HEIGHT=$FRAME_H"
      echo "GAL_SECONDARY_MARGINS=${MARGIN_W}x${MARGIN_H}"
      echo "GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4=$PIXEL_ASPECT_E4"
      echo "CLUSTERMAP_FULL_FRAME=$4"
      echo "CLUSTERMAP_720P=$HD720"
      echo "CLUSTERMAP_1080P=$HD1080"; } >> "$1.new" 2>/dev/null &&
    mv "$1.new" "$1" 2>/dev/null || { rm -f "$1.new" 2>/dev/null; return 1; }
    chmod 644 "$1" 2>/dev/null
    return 0
}
