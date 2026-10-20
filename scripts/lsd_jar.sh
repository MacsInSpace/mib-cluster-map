#!/bin/sh
# Add or remove ONE Java patch line in the interface start-up script (lsd.sh).
#
#   lsd_jar.sh add    <Name.jar> [source file]   copy the jar if missing or different, add its line
#   lsd_jar.sh remove <Name.jar>                 take its line out (the jar file stays)
#   lsd_jar.sh loaded <Name.jar>                 exit 0 if it is on a patch line
#
# The line is the one the toolbox and the jar projects themselves use:
#   BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/<Name.jar>"
# placed directly before the Java launch line. Other installers (CarPlay Maps
# VC) join their jar onto an existing line with ':', so a jar is looked up and
# removed as one entry of a line, never by deleting a line that lists others. A broken lsd.sh means the centre
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

# The entries of every patch line, one per line. Lines that are commented out
# are skipped: J9 never sees them.
entries()
{
    awk '/^[ \t]*#/ { next }
        {
            s = $0; i = index(s, "-Xbootclasspath/p:")
            if (i == 0) next
            s = substr(s, i + 18); j = index(s, "\""); if (j > 0) s = substr(s, 1, j - 1)
            n = split(s, e, ":"); for (k = 1; k <= n; k++) if (e[k] != "") print e[k]
        }' "$1"
}
is_ours() { awk -v n="/lsd/jars/$NAME" '{ if (substr($0, length($0) - length(n) + 1) == n) f = 1 } END { exit f ? 0 : 1 }'; }
loaded() { entries "$LSD" | is_ours; }
others() { entries "$1" | awk -v n="/lsd/jars/$NAME" 'substr($0, length($0) - length(n) + 1) != n'; }

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
        BEFORE=`wc -l < "$LSD"`
        mount -uw $APP; WRITABLE=1
        # Drop the jar's entry from each patch line. A line left with no
        # entries goes; a line that also lists other jars keeps them.
        awk -v n="/lsd/jars/$NAME" '
            function ours(x) { return substr(x, length(x) - length(n) + 1) == n }
            /^[ \t]*#/ { print; next }
            {
                i = index($0, "-Xbootclasspath/p:")
                if (i == 0) { print; next }
                head = substr($0, 1, i + 17); rest = substr($0, i + 18)
                j = index(rest, "\""); if (j == 0) { print; next }
                tail = substr(rest, j); m = split(substr(rest, 1, j - 1), e, ":")
                keep = ""; hit = 0
                for (k = 1; k <= m; k++) {
                    if (ours(e[k])) { hit = 1; continue }
                    if (e[k] != "") keep = (keep == "" ? e[k] : keep ":" e[k])
                }
                if (!hit) print
                else if (keep != "") print head keep tail
            }' "$LSD" > "$NEW"
        AFTER=`wc -l < "$NEW"`; DROPPED=`expr $BEFORE - $AFTER || true`  # expr exits 1 when the answer is 0
        [ "$DROPPED" -ge 0 ] && [ "$DROPPED" -le 1 ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
        if entries "$NEW" | is_ours; then echo "Entry still present after removal; lsd.sh not changed" >&2; exit 1; fi
        check_new || exit 1
        swap_in
        echo "Removed the $NAME entry. Previous file: $LSD.before_$TAG"
        ;;
    add)
        # Copy the jar when it is missing, or replace it when the bundled one
        # differs (a newer build). cmp is not on the unit, so compare sizes.
        if [ -n "$SRC" ] && [ -r "$SRC" ] && { [ ! -r "$JAR" ] || [ "`wc -c < "$SRC"`" != "`wc -c < "$JAR"`" ]; }; then
            mount -uw $APP; WRITABLE=1
            mkdir -p "$LSD_DIR/jars"
            cp "$SRC" "$JAR.new"
            [ "`wc -c < "$SRC"`" = "`wc -c < "$JAR.new"`" ] || { rm -f "$JAR.new"; echo "Jar copy failed" >&2; exit 1; }
            if [ -r "$JAR" ]; then cp -p "$JAR" "$JAR.before_update"; echo "Replacing $NAME (previous copy: $JAR.before_update)"; fi
            mv "$JAR.new" "$JAR"
            echo "Copied $NAME to $LSD_DIR/jars/"
        fi
        [ -r "$JAR" ] || { echo "Missing $JAR and no source file to copy" >&2; exit 1; }
        if loaded; then echo "$NAME is already loaded; nothing to add."; exit 0; fi
        BEFORE=`wc -l < "$LSD"`
        [ "`grep -c '^\$J9 ' "$LSD"`" -ge 1 ] || { echo "No Java launch line found in $LSD; not changed" >&2; exit 1; }
        mount -uw $APP; WRITABLE=1
        awk -v line="$LINE" '/^\$J9 /{print line} {print}' "$LSD" > "$NEW"
        [ `expr $BEFORE + 1` -eq "`wc -l < "$NEW"`" ] && entries "$NEW" | is_ours || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
        check_new || exit 1
        swap_in
        echo "Added the $NAME start-up line. Previous file: $LSD.before_$TAG"
        ;;
    *) echo "usage: $0 add|remove|loaded <Name.jar> [source file]" >&2; exit 2 ;;
esac
