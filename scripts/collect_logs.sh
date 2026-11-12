#!/bin/sh
# Run on the head unit after a test (green menu "Save logs to SD", or over SSH).
# Copies the hook and player logs plus system state to the SD card, into a
# new numbered folder each time (run_logs/1, run_logs/2, ...).
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
# The folder this script sits in is the package folder; logs go beside it.
HERE=`cd "\`dirname "$0"\`" && pwd`
SD=`dirname "$HERE"`
mount -uw "$SD" 2>/dev/null
N=1
while [ -e "$HERE/run_logs/$N" ]; do N=`expr $N + 1`; done
OUT=$HERE/run_logs/$N
mkdir -p $OUT
cp /tmp/gal_dualscreen.log /tmp/stream-player.log /tmp/gal_kombi_ready /tmp/clustermap_final.txt /tmp/VCAndroidAuto.log $OUT/ 2>/dev/null
sloginfo > $OUT/sloginfo.txt 2>&1
pidin ar > $OUT/pidin_ar.txt 2>&1
ls -l /mnt/ota /mnt/ota/* /var/dumps /tmp > $OUT/dumps_listing.txt 2>&1
# The software update's own records, if the unit keeps any.
ls -lR /mnt/ota/system/logs /net/rcc/tmp > $OUT/update_logs_listing.txt 2>&1
ls -l /lib/libEGL* /lib/libGLESv2* /usr/lib/libEGL* > $OUT/gl_libs.txt 2>&1
grep -n "gal" /mnt/system/etc/eso/production/smartphone_integrator.json > $OUT/gal_config_lines.txt 2>&1
sh $HERE/scripts/hook_status.sh > $OUT/status.txt 2>&1
grep -n 'Xbootclasspath' /mnt/app/eso/hmi/lsd/lsd.sh > $OUT/java_patches.txt 2>&1
# Audi lsd.sh loads every jar in lsd/jars by itself (#51): list them too.
{ echo "--- lsd/jars"; ls -l /mnt/app/eso/hmi/lsd/jars /mnt/app/eso/hmi/lsd/jars_off; } >> $OUT/java_patches.txt 2>&1
# dmdt buffers its output when it is not a terminal; the flush shim makes it
# write before it exits (as in GEM/collect_for_porting.sh).
# gd lists every window with its size; 33 is the stock cluster map.
for c in gs gd; do
    ( cd /eso && LD_PRELOAD="$HERE/lib/libdmdt_flush.so" LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib \
      IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt $c ) > $OUT/dmdt_$c.txt 2>&1
done
# What this unit is: which commands it lacks, and its gal against the profiles.
if [ -r "$HERE/scripts/lib_unit.sh" ]; then
    . "$HERE/scripts/lib_unit.sh"
    unit_tools
    unit_gal_check "$HERE"
    { echo "missing:$UNIT_MISSING"; echo "absent:$UNIT_ABSENT"; echo "$PROBE_OUT"; } > $OUT/unit_check.txt 2>&1
fi
# The cockpit display (window 33) only appears in 'gs' while the cockpit is in
# map view. Say so in the file, so a capture taken in another view is not read
# as a unit that cannot show a map. Audi uses context 72 (profiles.conf).
CTX=`sed -n 's/^GAL_VC_CONTEXT=\([0-9]*\).*/\1/p' /eso/lib/gal_dualscreen/gal_dualscreen.conf 2>/dev/null | head -1`
[ -n "$CTX" ] || CTX=70
if grep -q "context id: $CTX" $OUT/dmdt_gs.txt 2>/dev/null; then
    echo "NOTE: the cockpit display (context $CTX) is registered." >> $OUT/dmdt_gs.txt
else
    echo "NOTE: no cockpit display (context $CTX) at this moment. That is normal" >> $OUT/dmdt_gs.txt
    echo "unless the cockpit was in map view when these logs were saved." >> $OUT/dmdt_gs.txt
fi
# CarPlay map: the supervisor, its player, and harman-f's hook state.
mkdir -p $OUT/carplay
cp /tmp/carplay_cluster.log /tmp/stream-player-carplay.log /tmp/altscreen111.log \
   /tmp/mibr-carplay111.state /tmp/mibr-carplay111.heartbeat /tmp/mibr-alt111-gen2.status /tmp/clustermap-wheelzoom.log $OUT/carplay/ 2>/dev/null
grep -n -e dio_manager -e libcarplay -e ALTSCREEN111 /mnt/system/etc/eso/production/smartphone_integrator.json > $OUT/carplay/config_lines.txt 2>&1
grep -n carplay0 /mnt/system/etc/pf*.conf > $OUT/carplay/firewall_lines.txt 2>&1
sync 2>/dev/null
ls -l $OUT
echo "Done: ClusterMap/run_logs/$N. Wait a few seconds, then take the SD card to the laptop."
