#!/bin/sh
# Manage the start-up line that loads adi961's VCAndroidAuto.jar (turn-by-turn
# arrows) in the Java interface. The jar and the cluster map cannot both be
# active: with the jar loaded, the cluster goes blank when a route starts.
#
#   turn_by_turn.sh remove    take the line out (done by the map installer)
#   turn_by_turn.sh restore   put it back, only if "remove" took it out
#   turn_by_turn.sh install   copy the bundled jar if needed and add the line
#
# Only that one line of lsd.sh is ever added or removed. Every edit is written
# to a new file, checked, and only then moved into place; the previous file is
# kept beside it. Reboot afterwards.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
set -eu

HERE=`cd "\`dirname "$0"\`" && pwd`
APP=/mnt/app
LSD_DIR=$APP/eso/hmi/lsd
LSD=$LSD_DIR/lsd.sh
JAR=$LSD_DIR/jars/VCAndroidAuto.jar
MARKER=$LSD_DIR/.aacluster_tbt_removed
NEW=$LSD_DIR/lsd.sh.tbt_new
LINE='BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/VCAndroidAuto.jar"'
WRITABLE=0
finish() { if [ "$WRITABLE" -eq 1 ]; then rm -f "$NEW" 2>/dev/null || true; mount -ur $APP 2>/dev/null || true; fi; }
trap finish 0 1 2 15

[ -r "$LSD" ] || { echo "Missing $LSD" >&2; exit 1; }
loaded() { grep -q 'VCAndroidAuto.jar' "$LSD"; }

# Sanity checks every new lsd.sh must pass before it replaces the old one.
check_new()
{
    [ "`wc -l < "$NEW"`" -gt 100 ] || { echo "Result looks truncated; lsd.sh not changed" >&2; return 1; }
    grep -q 'Xbootclasspath/a:/ifs/lsd.jxe' "$NEW" || { echo "Main class path line missing; lsd.sh not changed" >&2; return 1; }
    grep -q '^\$J9 ' "$NEW" || { echo "Java launch line missing; lsd.sh not changed" >&2; return 1; }
    [ "`grep -c 'NavActiveIgnore.jar' "$NEW" || true`" = "`grep -c 'NavActiveIgnore.jar' "$LSD" || true`" ] || {
        echo "NavActiveIgnore line changed unexpectedly; lsd.sh not changed" >&2; return 1; }
    return 0
}

swap_in()   # swap_in <suffix for the saved copy>
{
    cp "$LSD" "$LSD.$1"
    chmod 755 "$NEW" 2>/dev/null || true
    mv "$NEW" "$LSD"
    sync
}

do_remove()
{
    if ! loaded; then echo "VCAndroidAuto.jar is not loaded; nothing to remove."; return 0; fi
    BEFORE=`wc -l < "$LSD"`; HITS=`grep -c 'VCAndroidAuto.jar' "$LSD"`
    mount -uw $APP; WRITABLE=1
    grep -v 'VCAndroidAuto.jar' "$LSD" > "$NEW"
    [ `expr $BEFORE - $HITS` -eq "`wc -l < "$NEW"`" ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
    check_new || exit 1
    swap_in before_tbt_remove
    : > "$MARKER"
    echo "Removed the VCAndroidAuto.jar start-up line ($HITS line). Previous file: $LSD.before_tbt_remove"
}

do_add()
{
    if loaded; then echo "VCAndroidAuto.jar is already loaded; nothing to add."; return 0; fi
    [ -r "$JAR" ] || { echo "Missing $JAR; cannot load it" >&2; exit 1; }
    BEFORE=`wc -l < "$LSD"`
    [ "`grep -c '^\$J9 ' "$LSD"`" -ge 1 ] || { echo "No Java launch line found in $LSD; not changed" >&2; exit 1; }
    mount -uw $APP; WRITABLE=1
    # Same place the jar's own installer uses: directly before each Java launch line.
    awk -v line="$LINE" '/^\$J9 /{print line} {print}' "$LSD" > "$NEW"
    ADDED=`grep -c 'VCAndroidAuto.jar' "$NEW"`
    [ `expr $BEFORE + $ADDED` -eq "`wc -l < "$NEW"`" ] && [ "$ADDED" -ge 1 ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
    check_new || exit 1
    swap_in before_tbt_add
    rm -f "$MARKER"
    echo "Added the VCAndroidAuto.jar start-up line. Previous file: $LSD.before_tbt_add"
}

case "${1:-}" in
    remove) do_remove ;;
    restore)
        if [ -f "$MARKER" ]; then do_add
        else echo "The installer did not remove a turn-by-turn jar on this unit; nothing to restore."; fi ;;
    install)
        if grep -q 'libgal_hook.so' /mnt/system/etc/eso/production/smartphone_integrator.json 2>/dev/null; then
            echo "The cluster map is installed. Uninstall it first; the two cannot run together." >&2; exit 1
        fi
        SRC="$HERE/thirdparty/VCAndroidAuto.jar"
        if [ ! -r "$JAR" ]; then
            [ -r "$SRC" ] || { echo "Missing $SRC" >&2; exit 1; }
            mount -uw $APP; WRITABLE=1
            mkdir -p "$LSD_DIR/jars"
            cp "$SRC" "$JAR.new"
            [ "`wc -c < "$SRC"`" = "`wc -c < "$JAR.new"`" ] || { rm -f "$JAR.new"; echo "Jar copy failed" >&2; exit 1; }
            mv "$JAR.new" "$JAR"
            echo "Copied the jar to $JAR"
        fi
        do_add ;;
    *) echo "usage: $0 remove|restore|install" >&2; exit 2 ;;
esac
echo "Reboot the unit to apply."
