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
# AU57x lsd.sh adds patch jars as BOOTCLASSPATH="...:jar" lines (lsd_jar.sh),
# which the Xbootclasspath line alone does not show.
grep -n -e 'Xbootclasspath' -e '^BOOTCLASSPATH=' /mnt/app/eso/hmi/lsd/lsd.sh > $OUT/java_patches.txt 2>&1
# Audi lsd.sh loads every jar in lsd/jars by itself (#51): list them too.
{ echo "--- lsd/jars"; ls -l /mnt/app/eso/hmi/lsd/jars /mnt/app/eso/hmi/lsd/jars_off; } >> $OUT/java_patches.txt 2>&1
# dmdt buffers its output when it is not a terminal; the flush shim makes it
# write before it exits (as in GEM/collect_for_porting.sh).
# gd lists every window with its size; 33 is the stock cluster map. gc lists
# every context with the windows it shows (#99, #105).
for c in gs gd gc; do
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
# Which builds of the shell and text tools this unit has (docs/Unit-shell.md:
# the simulator runs other builds of sed, grep and awk). There is no common
# version flag: GNU answers --version, the original awk -V or --version, and
# QNX's own tools may answer none, so every one is tried, with no input, and
# whatever comes back is kept. The size and path tell builds apart when
# nothing answers.
{
    echo "shell: ${KSH_VERSION:-no KSH_VERSION} (\$0=$0)"
    for t in sh ksh sed grep awk expr tail head wc find; do
        echo "--- $t"
        P=`command -v $t 2>/dev/null` || P=
        if [ -z "$P" ]; then echo "not found"; continue; fi
        ls -lL "$P" 2>&1
        for flag in --version -V -v; do
            echo "\$ $t $flag"
            $t $flag < /dev/null 2>&1 | head -3
        done
    done
} > $OUT/tool_versions.txt 2>&1
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
# Which window that context shows right now, against whether a player is
# running: a player that is drawing while the context is back on the car's own
# map window means something on the unit switched it back (#105, #24).
MINE=`sed -n 's/^GAL_VC_DISPLAYABLE_ID=\([0-9]*\).*/\1/p' /eso/lib/gal_dualscreen/gal_dualscreen.conf 2>/dev/null | head -1`
[ -n "$MINE" ] || MINE=3
SHOWN=`awk -v c="$CTX" '
    $1 == "context" && $2 == "id:" { f = ($3 == c); next }
    f && $1 ~ /^[0-9]+$/ { print $1; exit }' $OUT/dmdt_gs.txt 2>/dev/null`
PLAYER_UP=no
grep stream-player $OUT/pidin_ar.txt >/dev/null 2>&1 && PLAYER_UP=yes
{
    echo "context=$CTX shows_window=${SHOWN:-none} player_window=$MINE player_running=$PLAYER_UP"
    if [ "$PLAYER_UP" = yes ] && [ -n "$SHOWN" ] && [ "$SHOWN" != "$MINE" ]; then
        echo "CHECK: a player is running, but the cockpit context shows window $SHOWN,"
        echo "       not the player's ($MINE): the unit put its own map back while the"
        echo "       phone's picture was still being drawn."
    elif [ "$PLAYER_UP" = yes ] && [ -n "$SHOWN" ]; then
        echo "CHECK: a player is running and the cockpit context shows its window. OK."
    elif [ "$PLAYER_UP" = yes ]; then
        echo "CHECK: a player is running, but the cockpit context is not listed."
    else
        echo "CHECK: no player is running (no phone session at this moment)."
    fi
} > $OUT/context_check.txt 2>&1
cat $OUT/context_check.txt >> $OUT/dmdt_gs.txt 2>/dev/null
# CarPlay map: the supervisor, its player, and harman-f's hook state.
mkdir -p $OUT/carplay
cp /tmp/carplay_cluster.log /tmp/stream-player-carplay.log /tmp/altscreen111.log /tmp/altscreen111.log.1 \
   /tmp/mibr-carplay111.state /tmp/mibr-carplay111.heartbeat /tmp/mibr-alt111-gen2.status /tmp/clustermap-wheelzoom.log /tmp/clustermap-gfxstate.log $OUT/carplay/ 2>/dev/null
grep -n -e dio_manager -e libcarplay -e ALTSCREEN111 /mnt/system/etc/eso/production/smartphone_integrator.json > $OUT/carplay/config_lines.txt 2>&1
grep -n carplay0 /mnt/system/etc/pf*.conf > $OUT/carplay/firewall_lines.txt 2>&1
# CarPlay cover (#19, #62): the unit's iAP2 stack asks the iPhone for the
# artwork (iap2.cfg [nowplaying] ArtworkFileTransferIdentifier) and publishes
# now-playing to PPS, but DSICarplay never sent a cover to the cockpit jar.
# Read-only: where the artwork lands. Best taken while a CarPlay track plays.
# Plain sh, ls, sed and cat: find is not on every unit.
cover_paths()
{
    D=
    while read -r L; do
        case "$L" in
            */*:) D=${L%:} ;;
            *[Ii][Aa][Pp]*|*[Nn]ow[Pp]lay*|*[Aa]rtwork*|*[Ii][Pp]od*|*[Cc]ar[Pp]lay*|*[Cc]over*|*.jpg|*.jpeg|*.png)
                echo "$D/$L" ;;
        esac
    done
}
{
    echo "--- PPS entries about the phone's media"
    ls -R /pps 2>/dev/null | sed -n 1,4000p | cover_paths | sed -n 1,200p
    echo "--- image or artwork files in memory"
    ls -R /tmp /dev/shmem /var/tmp 2>/dev/null | sed -n 1,4000p | cover_paths | sed -n 1,200p
} > $OUT/carplay/cover_paths.txt 2>&1
{
    for P in `sed -n 's|^\(/pps/.*\)$|\1|p' $OUT/carplay/cover_paths.txt | sed -n 1,40p`; do
        if [ -f "$P" ]; then
            echo "=== $P"
            sed -n 1,80p "$P" 2>&1
        fi
    done
    echo "=== image files"
    for P in `sed -n '/^\/pps\//d; /^\//p' $OUT/carplay/cover_paths.txt | sed -n 1,40p`; do
        if [ -f "$P" ]; then ls -l "$P" 2>&1; fi
    done
} > $OUT/carplay/cover_pps.txt 2>&1
# Crash archives the unit's dumper keeps (pidin: dumper -d /mnt/ota/system/core).
# List them all, and copy the newest one of dio_manager (the CarPlay program,
# #111: CarPlay stops at start-up with NavActiveIgnore) and of gal (Android
# Auto; #127, #24 and #4 logged the same crash in gal at the phone's
# disconnect) when it is small.
CORE_DIR=${CLUSTERMAP_CORE_DIR:-/mnt/ota/system/core}
ls -l $CORE_DIR > $OUT/core_listing.txt 2>&1
for CORE_OF in dio_manager gal.core; do
    CORE=`ls -t $CORE_DIR/*$CORE_OF* 2>/dev/null | sed -n 1p`
    [ -n "$CORE" ] && [ -f "$CORE" ] || continue
    CORE_SIZE=`wc -c < "$CORE" | sed 's/ //g'`
    if [ "${CORE_SIZE:-0}" -gt 0 ] && [ "$CORE_SIZE" -le 8388608 ]; then
        if cp "$CORE" $OUT/carplay/ 2>/dev/null; then echo "copied: $CORE ($CORE_SIZE bytes)" >> $OUT/core_listing.txt; fi
    else
        echo "not copied (over 8 MB): $CORE ($CORE_SIZE bytes)" >> $OUT/core_listing.txt
    fi
done
# The two probes run last, each limited to PROBE_SECS, so a check that hangs
# on some unit costs only its own file, never the logs above: v1.2.10's tool
# probe stopped Save logs before the CarPlay files on a K3342 and a P3236
# (#62). Without sleep there is no way to time them, so they are left out.
PROBE_SECS=20
# limited NAME COMMAND...: run COMMAND in the background, stop it after
# PROBE_SECS, and say so in limits.txt.
limited()
{
    LN=$1; shift
    ${1+"$@"} &
    LP=$!
    LI=0
    while kill -0 $LP 2>/dev/null; do
        if [ $LI -ge $PROBE_SECS ]; then
            kill -9 $LP 2>/dev/null
            echo "$LN: stopped after $PROBE_SECS s" >> $OUT/limits.txt
            break
        fi
        sleep 1
        LI=`expr $LI + 1`
    done
    wait $LP 2>/dev/null || :
}
if command -v sleep >/dev/null 2>&1; then
    # The same checks the simulator runs (tests/unit_sim/probe_compare.sh).
    if [ -r "$HERE/scripts/unit_probe.sh" ]; then
        limited tool_probe sh "$HERE/scripts/unit_probe.sh" "$OUT/probe_work" > $OUT/tool_probe.txt 2>&1
        rm -rf "$OUT/probe_work" 2>/dev/null
    fi
    # Wireless groundwork (Android Auto and CarPlay without a cable): what
    # this unit has for it, read-only, with names and keys hidden.
    if [ -r "$HERE/scripts/wireless_probe.sh" ]; then
        limited wireless_probe sh "$HERE/scripts/wireless_probe.sh" "$OUT/wireless" > /dev/null 2>&1
    fi
else
    echo "probes skipped: no sleep command to time them" >> $OUT/limits.txt
fi
sync 2>/dev/null
ls -l $OUT
echo "Done: ClusterMap/run_logs/$N. Wait a few seconds, then take the SD card to the laptop."
