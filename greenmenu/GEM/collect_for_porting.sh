#!/bin/sh
# Copies the files needed to port this project to another firmware onto the
# SD card. Read-only on the unit; works on any firmware, installed or not.
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Android Auto cluster map: collect files for porting"
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
take /mnt/app/eso/lib/libautoreceiver.so
# Configuration the installer edits or reads.
take /mnt/system/etc/eso/production/smartphone_integrator.json
take /mnt/system/etc/eso/production/gal.json
take /mnt/system/etc/eso/production/displaymanager.json
take /mnt/app/eso/hmi/lsd/lsd.sh
# The Java interface image: needed only to port the turn-by-turn arrows, which
# are a Java patch built against it. About 55 MB.
if [ -r /ifs/lsd.jxe ]; then take /ifs/lsd.jxe; else take /mnt/app/eso/hmi/lsd/lsd.jxe; fi

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
echo "AACLUSTER_COLLECT_OK"
echo "Saved to: $OUT"
echo "These are Volkswagen/Harman firmware files. Do not post them publicly."
echo "See docs/Supported-Units.md for what to do with them."
exit 0
