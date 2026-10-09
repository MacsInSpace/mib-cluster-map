#!/bin/sh
# Add or remove ONE Java patch line in the interface start-up script (lsd.sh).
#
#   lsd_jar.sh add    <Name.jar> [source file]   copy the jar if missing, add its line
#   lsd_jar.sh remove <Name.jar>                 take its line out (the jar file stays)
#   lsd_jar.sh loaded <Name.jar>                 exit 0 if its line is present
#
# The line is the one the toolbox and the jar projects themselves use:
#   BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/<Name.jar>"
# placed directly before the Java launch line. A broken lsd.sh means the centre
# screen does not start, so every edit is written to a new file, checked, and
# only then moved into place; the previous file is kept as lsd.sh.before_<Name>.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
set -eu

APP=/mnt/app
LSD_DIR=$APP/eso/hmi/lsd
LSD=$LSD_DIR/lsd.sh
NEW=$LSD_DIR/lsd.sh.jar_new
ACTION=${1:-}
NAME=${2:-}
SRC=${3:-}
WRITABLE=0
finish() { if [ "$WRITABLE" -eq 1 ]; then rm -f "$NEW" 2>/dev/null || true; mount -ur $APP 2>/dev/null || true; fi; }
trap finish 0 1 2 15

case "$NAME" in
    *.jar) ;;
    *) echo "usage: $0 add|remove|loaded <Name.jar> [source file]" >&2; exit 2 ;;
esac
case "$NAME" in */*|*' '*) echo "Bad jar name" >&2; exit 2 ;; esac
[ -r "$LSD" ] || { echo "Missing $LSD" >&2; exit 1; }
JAR=$LSD_DIR/jars/$NAME
TAG=`echo "$NAME" | sed 's/\.jar$//'`
LINE="BOOTCLASSPATH=\"\$BOOTCLASSPATH -Xbootclasspath/p:\$BASE_DIR/lsd/jars/$NAME\""

loaded() { grep -q "/lsd/jars/$NAME\"" "$LSD"; }
others() { grep 'Xbootclasspath/p:' "$1" | grep -v "/lsd/jars/$NAME\"" || true; }

# Every new lsd.sh must pass these before it replaces the old one.
check_new()
{
    [ "`wc -l < "$NEW"`" -gt 100 ] || { echo "Result looks truncated; lsd.sh not changed" >&2; return 1; }
    grep -q 'Xbootclasspath/a:/ifs/lsd.jxe' "$NEW" || { echo "Main class path line missing; lsd.sh not changed" >&2; return 1; }
    grep -q '^\$J9 ' "$NEW" || { echo "Java launch line missing; lsd.sh not changed" >&2; return 1; }
    [ "`others "$NEW"`" = "`others "$LSD"`" ] || { echo "Other patch lines changed unexpectedly; lsd.sh not changed" >&2; return 1; }
    return 0
}

swap_in()
{
    cp "$LSD" "$LSD.before_$TAG"
    chmod 755 "$NEW" 2>/dev/null || true
    mv "$NEW" "$LSD"
    sync
}

case "$ACTION" in
    loaded)
        loaded ;;
    remove)
        if ! loaded; then echo "$NAME is not loaded; nothing to remove."; exit 0; fi
        BEFORE=`wc -l < "$LSD"`; HITS=`grep -c "/lsd/jars/$NAME\"" "$LSD"`
        mount -uw $APP; WRITABLE=1
        grep -v "/lsd/jars/$NAME\"" "$LSD" > "$NEW"
        [ `expr $BEFORE - $HITS` -eq "`wc -l < "$NEW"`" ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
        check_new || exit 1
        swap_in
        echo "Removed the $NAME start-up line. Previous file: $LSD.before_$TAG"
        ;;
    add)
        if loaded; then echo "$NAME is already loaded; nothing to add."; exit 0; fi
        if [ ! -r "$JAR" ]; then
            [ -n "$SRC" ] && [ -r "$SRC" ] || { echo "Missing $JAR and no source file to copy" >&2; exit 1; }
            mount -uw $APP; WRITABLE=1
            mkdir -p "$LSD_DIR/jars"
            cp "$SRC" "$JAR.new"
            [ "`wc -c < "$SRC"`" = "`wc -c < "$JAR.new"`" ] || { rm -f "$JAR.new"; echo "Jar copy failed" >&2; exit 1; }
            mv "$JAR.new" "$JAR"
            echo "Copied $NAME to $LSD_DIR/jars/"
        fi
        BEFORE=`wc -l < "$LSD"`
        [ "`grep -c '^\$J9 ' "$LSD"`" -ge 1 ] || { echo "No Java launch line found in $LSD; not changed" >&2; exit 1; }
        mount -uw $APP; WRITABLE=1
        awk -v line="$LINE" '/^\$J9 /{print line} {print}' "$LSD" > "$NEW"
        ADDED=`grep -c "/lsd/jars/$NAME\"" "$NEW"`
        [ "$ADDED" -ge 1 ] && [ `expr $BEFORE + $ADDED` -eq "`wc -l < "$NEW"`" ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
        check_new || exit 1
        swap_in
        echo "Added the $NAME start-up line. Previous file: $LSD.before_$TAG"
        ;;
    *) echo "usage: $0 add|remove|loaded <Name.jar> [source file]" >&2; exit 2 ;;
esac
