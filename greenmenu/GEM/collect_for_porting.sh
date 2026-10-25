#!/bin/sh
# Copies the files needed to port this project to another firmware onto the
# SD card. Read-only on the unit; works on any firmware, installed or not.
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Phone map on the digital cluster: collect files for porting"
echo "Firmware train: $TRAIN"
NAME=`echo "$TRAIN" | sed 's/[^A-Za-z0-9_.-]/_/g'`
[ -n "$NAME" ] || NAME=unknown
OUT="$PKG/porting_$NAME"
mkdir -p "$OUT" || { echo "Cannot write to the SD card."; exit 0; }
INFO="$OUT/info.txt"
echo "train=$TRAIN" > "$INFO"

say() { echo "$1"; echo "$1" >> "$INFO"; }
take()   # take <source file> : copy one file and record its size
{
    if [ -r "$1" ]; then
        if cp "$1" "$OUT/" 2>/dev/null; then
            say "copied  `wc -c < "$1" | sed 's/ //g'` bytes  $1"
        else
            say "FAILED  $1"
        fi
    else
        say "missing $1"
    fi
}

# The Android Auto program and its receiver library: what the hook attaches to.
take /mnt/app/eso/bin/apps/gal

# The receiver library is not always in the same place: on the tested units it
# is at both /mnt/app/eso/lib and /eso/lib. Try the known paths, then look for
# it, so "missing" means it really is not on the unit.
take_receiver()
{
    for p in /mnt/app/eso/lib/libautoreceiver.so /eso/lib/libautoreceiver.so \
             /mnt/app/armle/lib/libautoreceiver.so /mnt/app/usr/lib/libautoreceiver.so \
             /mnt/app/root/lib-target/libautoreceiver.so; do
        if [ -r "$p" ]; then take "$p"; return; fi
    done
    found=`find /mnt/app/eso/lib /eso/lib /mnt/app/armle/lib /mnt/app/usr/lib \
                /mnt/app/root/lib-target -name 'libautoreceiver*.so' 2>/dev/null | head -1`
    if [ -n "$found" ]; then take "$found"; return; fi
    say "missing libautoreceiver.so (looked in the usual library folders)"
    # Say what the Android Auto program itself asks for, so a unit that names
    # the library differently can still be ported.
    needs=`grep -a -o 'lib[A-Za-z0-9_-]*\.so[.0-9]*' /mnt/app/eso/bin/apps/gal 2>/dev/null \
           | sort -u | tr '\n' ' '`
    [ -n "$needs" ] && say "gal asks for: $needs"
}
take_receiver
# Configuration the installer edits or reads.
take /mnt/system/etc/eso/production/smartphone_integrator.json
take /mnt/system/etc/eso/production/gal.json
take /mnt/system/etc/eso/production/displaymanager.json
take /mnt/app/eso/hmi/lsd/lsd.sh
# The Java interface image: needed only to port the turn-by-turn arrows, which
# are a Java patch built against it. About 55 MB.
# Only copied when asked for with --full: it is slow, and a cluster map port
# does not need it.
if [ "${1:-}" != "--full" ]; then
    say "skipped lsd.jxe (only needed for a turn-arrows port; use the full collection for it)"
elif [ -r /ifs/lsd.jxe ]; then take /ifs/lsd.jxe; else take /mnt/app/eso/hmi/lsd/lsd.jxe; fi

# Which window carries the cluster map, from the boot log and the display table.
echo "--- first-swap lines from the system log" >> "$INFO"
sloginfo 2>/dev/null | grep "performed 1st swap" >> "$INFO" 2>&1
echo "--- display table (dmdt gs)" >> "$INFO"
if [ -x /eso/bin/apps/dmdt ]; then
    ( cd /eso && LD_PRELOAD="$PKG/lib/libdmdt_flush.so" LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib \
      IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt gs ) >> "$INFO" 2>&1
else
    echo "dmdt not found" >> "$INFO"
fi
echo "--- Java patches loaded" >> "$INFO"
grep -n "bootclasspath/p" /mnt/app/eso/hmi/lsd/lsd.sh >> "$INFO" 2>&1
sync 2>/dev/null

echo
echo "CLUSTERMAP_COLLECT_OK"
echo "Saved to: $OUT"
echo "These are Volkswagen/Harman firmware files. Do not post them publicly."
echo "See docs/Install.md, "Getting your unit added", for what to do with them."
exit 0
