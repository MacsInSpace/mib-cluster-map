#!/bin/sh
. "`dirname "$0"`/common.sh"
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
LSD=/mnt/app/eso/hmi/lsd/lsd.sh
echo "Phone map on the digital cluster: status"
echo "Package folder: $PKG"
echo "Firmware train: $TRAIN"
if train_supported; then echo "  supported: yes ($SUPPORT_NOTE)"; else echo "  supported: NO ($SUPPORT_NOTE)"; fi
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null; then echo "Hook: installed"; else echo "Hook: not installed"; fi
if [ -f /mnt/app/eso/lib/gal_dualscreen/libgal_hook.so ]; then echo "  library: present"; else echo "  library: missing"; fi
if [ -f /mnt/app/navigation/stream-player ]; then echo "  player: present"; else echo "  player: missing"; fi
if grep -q 'libcarplay_cluster.so' "$CONFIG" 2>/dev/null; then
    echo "CarPlay map: installed, `sed -n 's/.*"ALTSCREEN111_WIDTH=\([0-9]*\)", "ALTSCREEN111_HEIGHT=\([0-9]*\)".*/\1x\2/p' "$CONFIG"`"
    if [ -r /tmp/mibr-carplay111.state ]; then echo "  CarPlay cluster stream: `cat /tmp/mibr-carplay111.state`"; else echo "  CarPlay cluster stream: none yet (connect an iPhone)"; fi
    if sh "$PKG/lsd_jar.sh" loaded ClusterMapWheelZoom.jar; then
        if [ -f /mnt/app/eso/lib/gal_dualscreen/wheel_zoom_reverse ]; then echo "  steering-wheel zoom: loaded, reversed"; else echo "  steering-wheel zoom: loaded"; fi
        [ -r /tmp/clustermap-wheelzoom.log ] && tail -2 /tmp/clustermap-wheelzoom.log | sed 's/^/    /'
    elif sh "$PKG/lsd_jar.sh" loaded ClusterMapNavAsiaZoom.jar; then
        if [ -r /mnt/app/eso/lib/gal_dualscreen/wheel_zoom_id ]; then echo "  steering-wheel zoom: loaded, roller id `cat /mnt/app/eso/lib/gal_dualscreen/wheel_zoom_id`"
        else echo "  steering-wheel zoom: loaded, log only (no roller id set)"; fi
        [ -f /mnt/app/eso/lib/gal_dualscreen/wheel_zoom_reverse ] && echo "    reversed"
        [ -r /tmp/clustermap-wheelzoom.log ] && tail -4 /tmp/clustermap-wheelzoom.log | sed 's/^/    /'
    fi
else
    # The library is not in the same folder on every unit: found as the
    # installer finds it (common.sh).
    ap=`airplay_path`
    a=
    if [ -n "$ap" ]; then a=`wc -c < "$ap" 2>/dev/null | sed 's/ //g'`; fi
    if [ "$a" = 703688 ] || [ "$a" = 694088 ]; then echo "CarPlay map: not installed (this unit's CarPlay library is supported)"
    elif [ -n "$a" ]; then echo "CarPlay map: not installed (CarPlay library $a bytes; tested: 703688 and 694088. Another build needs CLUSTERMAP_CARPLAY_TRIAL, see Install)"
    else echo "CarPlay map: not installed (no CarPlay library found on this unit)"; fi
fi
if sh "$PKG/lsd_jar.sh" loaded NavActiveIgnore.jar; then echo "NavActiveIgnore: loaded (required)"
elif sh "$PKG/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then echo "NavActiveIgnore: loaded as CarPlay's CarPlayNavigationPatch.jar (same patch)"
else echo "NavActiveIgnore: not loaded (Install adds it on tested firmware)"; fi
if sh "$PKG/lsd_jar.sh" loaded VCAndroidAuto.jar; then echo "Turn-by-turn arrows (VCAndroidAuto.jar): loaded. Installing the map turns this off."; else echo "Turn-by-turn arrows (VCAndroidAuto.jar): not loaded"; fi
echo "Java patch lines:"
grep -n 'Xbootclasspath/p' "$LSD" 2>/dev/null | sed 's|.*/p:||; s|\$BASE_DIR/lsd/jars/||g; s|"$||; s|^|  |'
if [ -r /tmp/gal_dualscreen.log ]; then
    echo "Last hook events:"
    grep -E "event=(init |firmware.verify|secondary.register|focus.state|player.spawn|focus.loss)" /tmp/gal_dualscreen.log | tail -6 | sed -e 's/^gal_dualscreen //' -e 's/^\(.\{110\}\).*/\1/'
else
    echo "No hook log yet (connect a phone after rebooting)."
fi
exit 0
