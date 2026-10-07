#!/bin/sh
# Take adi961's VCAndroidAuto.jar out of the Java interface start-up line.
#
#   sh /fs/sda0/remove_turn_by_turn_jar.sh            remove it
#   sh /fs/sda0/remove_turn_by_turn_jar.sh --restore  put the previous lsd.sh back
#
# Only the one line that loads VCAndroidAuto.jar is removed from lsd.sh. The
# NavActiveIgnore line and everything else stay. The jar file itself is left in
# place; without its line in lsd.sh it is never loaded. Reboot afterwards.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
set -eu

APP=/mnt/app
LSD=$APP/eso/hmi/lsd/lsd.sh
SAVED=$APP/eso/hmi/lsd/lsd.sh.before_tbt_remove
NEW=$APP/eso/hmi/lsd/lsd.sh.tbt_new
WRITABLE=0
finish() { [ "$WRITABLE" -eq 1 ] && { rm -f "$NEW" 2>/dev/null || true; mount -ur $APP 2>/dev/null || true; }; }
trap finish 0 1 2 15

[ -r "$LSD" ] || { echo "Missing $LSD" >&2; exit 1; }

if [ "${1:-}" = "--restore" ]; then
    [ -r "$SAVED" ] || { echo "No saved copy at $SAVED; nothing to restore" >&2; exit 1; }
    mount -uw $APP; WRITABLE=1
    cp "$SAVED" "$NEW"
    chmod 755 "$NEW" 2>/dev/null || true
    mv "$NEW" "$LSD"
    sync
    echo "Restored $LSD from $SAVED. Reboot the unit."
    exit 0
fi

if ! grep -q 'VCAndroidAuto.jar' "$LSD"; then
    echo "VCAndroidAuto.jar is not loaded by $LSD; nothing to do."
    exit 0
fi

BEFORE=`wc -l < "$LSD"`
HITS=`grep -c 'VCAndroidAuto.jar' "$LSD"`
HAD_NAVIGNORE=`grep -c 'NavActiveIgnore.jar' "$LSD" || true`
mount -uw $APP; WRITABLE=1
grep -v 'VCAndroidAuto.jar' "$LSD" > "$NEW"
AFTER=`wc -l < "$NEW"`
# Exactly the matching lines must be gone, and nothing else.
[ `expr $BEFORE - $HITS` -eq "$AFTER" ] || { echo "Line count check failed ($BEFORE - $HITS != $AFTER); lsd.sh not changed" >&2; exit 1; }
[ "$AFTER" -gt 100 ] || { echo "Result looks truncated ($AFTER lines); lsd.sh not changed" >&2; exit 1; }
[ "`grep -c 'NavActiveIgnore.jar' "$NEW" || true`" -eq "$HAD_NAVIGNORE" ] || { echo "NavActiveIgnore line changed unexpectedly; lsd.sh not changed" >&2; exit 1; }
grep -q 'Xbootclasspath/a:/ifs/lsd.jxe' "$NEW" || { echo "Main class path line missing from result; lsd.sh not changed" >&2; exit 1; }
[ -r "$SAVED" ] || cp "$LSD" "$SAVED"
chmod 755 "$NEW" 2>/dev/null || true
mv "$NEW" "$LSD"
sync
echo "Removed the VCAndroidAuto.jar line from $LSD ($HITS line)."
echo "Previous file saved as $SAVED."
echo "Reboot the unit. To undo: sh $0 --restore"
