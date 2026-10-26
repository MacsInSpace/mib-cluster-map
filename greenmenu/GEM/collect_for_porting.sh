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

# A library this project attaches to, under whatever name this unit carries.
# The known names come first (lib_path in common.sh); if none of them is
# there, look for anything matching the glob and COPY what turns up rather
# than only reporting it. On the VWG11 generation the name itself was the
# discovery (issue #28), and a file on the card is worth more than a line in
# a log. One copy per distinct filename, since the tested units carry the
# same library at two paths. The glob deliberately has no .so suffix, so it
# matches libautoreceiver_qnx.so.1 as well. /net is left out on purpose: it
# is the other QNX node over QNET and walking it is slow.
#
# Returns 1 when nothing was found, so the caller can explain its own case.
take_lib()   # take_lib <label> <glob> <known name>...
{
    what=$1; glob=$2; shift 2
    found=`lib_path "$@"`
    if [ -n "$found" ]; then take "$found"; return 0; fi
    names=
    for f in `find $LIB_DIRS /mnt/app /mnt/system /eso /lib /usr/lib \
                   -name "$glob" 2>/dev/null`; do
        b=`echo "$f" | sed 's|.*/||'`
        case " $names " in *" $b "*) continue ;; esac
        names="$names $b"
        take "$f"
    done
    if [ -n "$names" ]; then
        say "$what found under another name:$names"
        return 0
    fi
    return 1
}
if ! take_lib 'the Android Auto receiver' 'libautoreceive*' $RECEIVER_NAMES; then
    say "missing the Android Auto receiver: looked for $RECEIVER_NAMES in the usual folders"
    # Say what the Android Auto program itself asks for, so a unit that names
    # the library differently can still be ported. Joined with the shell, not
    # with tr: some units have no tr binary (issue #28).
    needs=
    for n in `grep -a -o 'lib[A-Za-z0-9_-]*\.so[.0-9]*' /mnt/app/eso/bin/apps/gal 2>/dev/null | sort -u`; do
        needs="$needs $n"
    done
    [ -n "$needs" ] && say "gal asks for:$needs"
fi
# The CarPlay library, for a CarPlay port. Its absence is not a problem for
# the Android Auto map, so it is only noted.
if ! take_lib 'the CarPlay library' 'libairplay*' $AIRPLAY_NAMES; then
    say "missing libairplay.so (CarPlay library): CarPlay cannot be ported from this collection"
fi
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
