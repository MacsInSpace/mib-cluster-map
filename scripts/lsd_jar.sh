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
#
# Audi lsd.sh (AU37x P5089, AUG22 K3346) has no such lines: it puts every
# .jar and .zip under lsd/jars/ on the class path itself, and its launch line
# is indented. There a jar is loaded when its file is in jars/; "add" only
# copies it, and "remove" moves it to jars_off/, so lsd.sh is never edited
# (#51: "No Java launch line found", though the copied jar was already live).
#
# AU57x lsd.sh (A6/A7 C7.5, K3663) starts J9 with -Xbootclasspath:$BOOTCLASSPATH
# and builds that path one line at a time; a patch jar is a line of its own
# before lsd.jxe's, which is how M.I.B. adds its jars there:
#   BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/<Name.jar>"
# "add" puts that line directly before
#   BOOTCLASSPATH="$BOOTCLASSPATH:$LSD_DIR/lsd.jxe"
# and "remove" takes exactly that line out again.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
set -eu

# tests/lsd_jar_test.sh runs this against copies, with no mounts.
APP=${LSD_JAR_TEST_APP:-/mnt/app}
app_rw() { [ -n "${LSD_JAR_TEST_APP:-}" ] || mount -uw $APP; }
app_ro() { [ -n "${LSD_JAR_TEST_APP:-}" ] || mount -ur $APP 2>/dev/null || true; }
LSD_DIR=$APP/eso/hmi/lsd
JARS_DIR=$LSD_DIR/jars
LSD=$LSD_DIR/lsd.sh
NEW=$LSD_DIR/lsd.sh.jar_new
ACTION=${1:-}
NAME=${2:-}
SRC=${3:-}
WRITABLE=0
finish() { if [ "$WRITABLE" -eq 1 ]; then rm -f "$NEW" 2>/dev/null || true; app_ro; fi; }
trap finish 0 1 2 15

case "$NAME" in
    *.jar) ;;
    *) echo "usage: $0 add|remove|loaded <Name.jar> [source file]" >&2; exit 2 ;;
esac
case "$NAME" in */*|*' '*) echo "Bad jar name" >&2; exit 2 ;; esac
[ -r "$LSD" ] || { echo "Missing $LSD" >&2; exit 1; }
JAR=$LSD_DIR/jars/$NAME
TAG=`echo "$NAME" | sed 's/\.jar$//'`
JARS_OFF=$LSD_DIR/jars_off
# if, not "[ ] &&" (set -e)
AUTOJARS=0
if grep -q 'find \$BASE_DIR/lsd/jars' "$LSD"; then AUTOJARS=1; fi
LINE="BOOTCLASSPATH=\"\$BOOTCLASSPATH -Xbootclasspath/p:\$BASE_DIR/lsd/jars/$NAME\""
# AU37x BOOTPREPEND pattern: -Xbootclasspath/p:$JARS_DIR/$NAME must come
# AFTER -Xbootclasspath:$BOOTCLASSPATH on the $J9 launch line, because
# -Xbootclasspath:$BOOTCLASSPATH overwrites any earlier -Xbootclasspath/p:.
BPCP_LINE="-Xbootclasspath:\$BOOTCLASSPATH -Xbootclasspath/p:$JARS_DIR/$NAME"
# Legacy VMOPTIONS line from an earlier (broken) install to clean up.
VMOPT_LINE="VMOPTIONS=\"\$VMOPTIONS -Xbootclasspath/p:$JARS_DIR/$NAME\""
# AU57x layout (see the top): the jar's own line, and the lsd.jxe line it
# must come before to replace classes in it.
JXECP=0
JXE_LINE='BOOTCLASSPATH="$BOOTCLASSPATH:$LSD_DIR/lsd.jxe"'
JAR_LINE="BOOTCLASSPATH=\"\$BOOTCLASSPATH:/eso/hmi/lsd/jars/$NAME\""
if [ "$AUTOJARS" -eq 0 ] && grep -q 'Xbootclasspath:\$BOOTCLASSPATH' "$LSD" &&
   awk -v j="$JXE_LINE" '$0 == j { f = 1 } END { exit f ? 0 : 1 }' "$LSD"; then
    JXECP=1
fi
# AU37x layout (AUTOJARS=1): lsd.sh loads every jar in jars/ on BOOTCLASSPATH,
# but lsd.jxe's classes win over those. A jar that replaces a stock class
# (only the cover-art hook, #195) is also put on the $J9 launch line with
# -Xbootclasspath/p:, after -Xbootclasspath:$BOOTCLASSPATH. Every other jar
# (NavActiveIgnore) is only copied, and lsd.sh stays as it is.
PREPEND_JARS=${LSD_JAR_TEST_PREPEND:-AAcoverart_hook.jar}
BOOTPREPEND=0
case " $PREPEND_JARS " in
    *" $NAME "*)
        if [ "$AUTOJARS" -eq 1 ] && grep -q '\$J9 ' "$LSD" && grep -q '\-jxe:' "$LSD"; then BOOTPREPEND=1; fi ;;
esac

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
# The jar's AU57x line, before the lsd.jxe line (after it, it replaces nothing).
jxe_loaded()
{
    awk -v j="$JXE_LINE" -v l="$JAR_LINE" '$0 == j { exit } $0 == l { f = 1; exit } END { exit f ? 0 : 1 }' "$1"
}
loaded()
{
    if [ "$AUTOJARS" -eq 1 ]; then
        if [ "$BOOTPREPEND" -eq 1 ]; then
            [ -f "$JAR" ] || return 1
            awk -v v="$BPCP_LINE" 'index($0, v) { f = 1; exit } END { exit f ? 0 : 1 }' "$LSD"
            return
        fi
        [ -f "$JAR" ]; return
    fi
    if [ "$JXECP" -eq 1 ] && jxe_loaded "$LSD"; then return 0; fi
    entries "$LSD" | is_ours
}
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

# AU57x: the new file is the old one with only the jar's line added or taken
# out, and still has the lsd.jxe line and the Java launch.
check_new_jxecp()
{
    [ "`wc -l < "$NEW"`" -gt 50 ] || { echo "Result looks truncated; lsd.sh not changed" >&2; return 1; }
    awk -v j="$JXE_LINE" '$0 == j { f = 1 } END { exit f ? 0 : 1 }' "$NEW" || { echo "lsd.jxe line missing; lsd.sh not changed" >&2; return 1; }
    grep -q 'Xbootclasspath:\$BOOTCLASSPATH' "$NEW" || { echo "Java launch line missing; lsd.sh not changed" >&2; return 1; }
    awk -v l="$JAR_LINE" '
        FNR == 1 { file++ }
        $0 == l { next }
        file == 1 { a[++n] = $0; next }
        { if (a[++m] != $0) bad = 1 }
        END { exit (bad || m != n) ? 1 : 0 }' "$LSD" "$NEW" || { echo "Other lines changed unexpectedly; lsd.sh not changed" >&2; return 1; }
    return 0
}

# AU37x: the new file must still have the $J9 launch line with -jxe:,
# the legacy VMOPTIONS line removed, and all other lines unchanged.
# For "add", -Xbootclasspath/p:$JARS_DIR/$NAME must be on the $J9 line
# after -Xbootclasspath:$BOOTCLASSPATH. For "remove", it must not be.
check_new_bootprepend()
{
    BP_OP=${1:-add}
    [ "`wc -l < "$NEW"`" -gt 50 ] || { echo "Result looks truncated; lsd.sh not changed" >&2; return 1; }
    grep -q '\$J9 ' "$NEW" || { echo "Java launch line missing; lsd.sh not changed" >&2; return 1; }
    grep -q '\-jxe:' "$NEW" || { echo "lsd.jxe launch line missing; lsd.sh not changed" >&2; return 1; }
    if [ "$BP_OP" = add ]; then
        awk -v v="$BPCP_LINE" 'index($0, v) { f = 1; exit } END { exit f ? 0 : 1 }' "$NEW" || { echo "BOOTPREPEND line missing; lsd.sh not changed" >&2; return 1; }
        # Verify BPCP_LINE comes after -Xbootclasspath:$BOOTCLASSPATH on the same line
        awk -v b="$BPCP_LINE" '
            /\$J9 / {
                i = index($0, "-Xbootclasspath:$BOOTCLASSPATH")
                j = index($0, "-Xbootclasspath/p:")
                if (i == 0 || j == 0 || j <= i) bad = 1
            }
            END { exit bad ? 1 : 0 }' "$NEW" || { echo "BOOTPREPEND not after -Xbootclasspath on $J9 line; lsd.sh not changed" >&2; return 1; }
    fi
    awk -v v="$VMOPT_LINE" 'index($0, v) { f = 1; exit } END { exit f ? 0 : 1 }' "$NEW" && { echo "Legacy VMOPTIONS line still present; lsd.sh not changed" >&2; return 1; }
    awk -v v="$VMOPT_LINE" '
        FNR == 1 { file++ }
        $0 == v { next }
        /\$J9 / { next }
        file == 1 { a[++n] = $0; next }
        { if (a[++m] != $0) bad = 1 }
        END { exit (bad || m != n) ? 1 : 0 }' "$LSD" "$NEW" || { echo "Other lines changed unexpectedly; lsd.sh not changed" >&2; return 1; }
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
        if [ "$AUTOJARS" -eq 1 ]; then
            app_rw; WRITABLE=1
            if [ "$BOOTPREPEND" -eq 1 ] && awk -v v="$BPCP_LINE" 'index($0, v) { f = 1; exit } END { exit f ? 0 : 1 }' "$LSD"; then
                # Remove -Xbootclasspath/p:$JARS_DIR/$NAME from the $J9 line,
                # keeping -Xbootclasspath:$BOOTCLASSPATH intact.
                awk -v p="$JARS_DIR/$NAME" '
                    /\$J9 / {
                        s = "-Xbootclasspath:$BOOTCLASSPATH -Xbootclasspath/p:" p
                        i = index($0, s)
                        if (i > 0) {
                            $0 = substr($0, 1, i - 1) "-Xbootclasspath:$BOOTCLASSPATH" substr($0, i + length(s))
                        }
                    }
                    { print }
                ' "$LSD" > "$NEW"
                # Also remove any legacy VMOPTIONS line from an earlier install.
                awk -v v="$VMOPT_LINE" 'index($0, v) == 0 { print }' "$NEW" > "$NEW.tmp"
                mv "$NEW.tmp" "$NEW"
                check_new_bootprepend remove || exit 1
                swap_in
                echo "Removed -Xbootclasspath/p: for $NAME. Previous file: $LSD.before_$TAG"
            fi
            mkdir -p "$JARS_OFF"
            mv "$JAR" "$JARS_OFF/$NAME"
            sync
            echo "Moved $NAME out of $LSD_DIR/jars/ (this lsd.sh loads every jar there): $JARS_OFF/$NAME"
            exit 0
        fi
        BEFORE=`wc -l < "$LSD"`
        if [ "$JXECP" -eq 1 ] && awk -v l="$JAR_LINE" '$0 == l { f = 1 } END { exit f ? 0 : 1 }' "$LSD"; then
            app_rw; WRITABLE=1
            awk -v l="$JAR_LINE" '$0 != l' "$LSD" > "$NEW"
            AFTER=`wc -l < "$NEW"`
            [ "$AFTER" -lt "$BEFORE" ] || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
            if jxe_loaded "$NEW"; then echo "Line still present after removal; lsd.sh not changed" >&2; exit 1; fi
            check_new_jxecp || exit 1
            swap_in
            echo "Removed the $NAME line. Previous file: $LSD.before_$TAG"
            exit 0
        fi
        app_rw; WRITABLE=1
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
            app_rw; WRITABLE=1
            mkdir -p "$LSD_DIR/jars"
            cp "$SRC" "$JAR.new"
            [ "`wc -c < "$SRC"`" = "`wc -c < "$JAR.new"`" ] || { rm -f "$JAR.new"; echo "Jar copy failed" >&2; exit 1; }
            if [ -r "$JAR" ]; then cp -p "$JAR" "$JAR.before_update"; echo "Replacing $NAME (previous copy: $JAR.before_update)"; fi
            mv "$JAR.new" "$JAR"
            echo "Copied $NAME to $LSD_DIR/jars/"
        fi
        if [ ! -r "$JAR" ] && [ "$AUTOJARS" -eq 1 ] && [ -r "$JARS_OFF/$NAME" ]; then
            app_rw; WRITABLE=1
            mv "$JARS_OFF/$NAME" "$JAR"
            echo "Moved $NAME back to $LSD_DIR/jars/"
        fi
        [ -r "$JAR" ] || { echo "Missing $JAR and no source file to copy" >&2; exit 1; }
        if [ "$AUTOJARS" -eq 1 ]; then
            if [ "$BOOTPREPEND" -eq 1 ]; then
                app_rw; WRITABLE=1
                if ! awk -v v="$BPCP_LINE" 'index($0, v) { f = 1; exit } END { exit f ? 0 : 1 }' "$LSD"; then
                    # Add -Xbootclasspath/p:$JARS_DIR/$NAME after -Xbootclasspath:$BOOTCLASSPATH
                    # on the $J9 launch line (NOT on VMOPTIONS, which comes before it).
                    awk -v p="$JARS_DIR/$NAME" '
                        /\$J9 / {
                            s = "-Xbootclasspath:$BOOTCLASSPATH"
                            i = index($0, s)
                            if (i > 0) {
                                end = i + length(s)
                                $0 = substr($0, 1, end - 1) " -Xbootclasspath/p:" p substr($0, end)
                            }
                        }
                        { print }
                    ' "$LSD" > "$NEW"
                    # Also remove any legacy VMOPTIONS line from an earlier install.
                    awk -v v="$VMOPT_LINE" 'index($0, v) == 0 { print }' "$NEW" > "$NEW.tmp"
                    mv "$NEW.tmp" "$NEW"
                    check_new_bootprepend add || exit 1
                    swap_in
                    echo "Added -Xbootclasspath/p: for $NAME after -Xbootclasspath:\$BOOTCLASSPATH. Previous file: $LSD.before_$TAG"
                else
                    echo "$NAME already prepended via -Xbootclasspath/p:; lsd.sh not changed."
                fi
            fi
            echo "$NAME is in $LSD_DIR/jars/, which this lsd.sh loads by itself."
            exit 0
        fi
        if loaded; then echo "$NAME is already loaded; nothing to add."; exit 0; fi
        BEFORE=`wc -l < "$LSD"`
        if [ "$JXECP" -eq 1 ]; then
            app_rw; WRITABLE=1
            awk -v j="$JXE_LINE" -v l="$JAR_LINE" '!done && $0 == j { print l; done = 1 } { print }' "$LSD" > "$NEW"
            [ `expr $BEFORE + 1` -eq "`wc -l < "$NEW"`" ] && jxe_loaded "$NEW" || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
            check_new_jxecp || exit 1
            swap_in
            echo "Added the $NAME line before lsd.jxe. Previous file: $LSD.before_$TAG"
            exit 0
        fi
        [ "`grep -c '^\$J9 ' "$LSD"`" -ge 1 ] || { echo "No Java launch line found in $LSD; not changed" >&2; exit 1; }
        app_rw; WRITABLE=1
        awk -v line="$LINE" '/^\$J9 /{print line} {print}' "$LSD" > "$NEW"
        [ `expr $BEFORE + 1` -eq "`wc -l < "$NEW"`" ] && entries "$NEW" | is_ours || { echo "Line count check failed; lsd.sh not changed" >&2; exit 1; }
        check_new || exit 1
        swap_in
        echo "Added the $NAME start-up line. Previous file: $LSD.before_$TAG"
        ;;
    *) echo "usage: $0 add|remove|loaded <Name.jar> [source file]" >&2; exit 2 ;;
esac
