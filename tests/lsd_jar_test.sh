#!/bin/bash
# lsd_jar.sh against copies of the two lsd.sh layouts it edits, with no
# mounts (LSD_JAR_TEST_APP): add, add again, remove, and the file must come
# back byte for byte. A wrong edit of lsd.sh stops the centre screen.
#
#   tests/lsd_jar_test.sh [real lsd.sh ...]
#
# Extra arguments are real lsd.sh files to run the same cycle on (a unit's
# lsd.sh holds its VIN: keep those out of the repository).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok    $*"; }
bad() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }

# AU57x (K3663): -Xbootclasspath:$BOOTCLASSPATH, M.I.B. jars as lines before lsd.jxe.
au57x() {
    echo '#!/bin/sh'
    echo 'export LSD_DIR=/ifs'
    for i in $(seq 1 70); do echo "VMOPTIONS=\"\$VMOPTIONS -Dfiller$i=1\""; done
    echo '# M.I.B. NavActiveIgnore AU57x'
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/NavActiveIgnore.jar"'
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/CarplayTouchpadMIB.jar"'
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH:$LSD_DIR/lsd.jxe"'
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/lang_data.zip:/eso/hmi/lsd/jars/ext_logs.zip"'
    echo ''
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:/eso/hmi/lsd/jars/NavActiveIgnore.jar"'
    echo 'on -p 12 /ifs/jre/bin/j9 $VMOPTIONS -Xbootclasspath:$BOOTCLASSPATH -jxe:$LSD_DIR/lsd.jxe &'
}

# VW (P4521 and others): patch lines before the "$J9 " launch line.
vw() {
    echo '#!/bin/sh'
    for i in $(seq 1 110); do echo "VMOPTIONS=\"\$VMOPTIONS -Dfiller$i=1\""; done
    echo 'BOOTCLASSPATH="-Xbootclasspath/a:/ifs/lsd.jxe"'
    echo 'BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/NavActiveIgnore.jar"'
    echo '$J9 $VMOPTIONS $BOOTCLASSPATH -jxe:/ifs/lsd.jxe &'
}

# AU37x (P5089): lsd.sh loads every jar in jars/ on BOOTCLASSPATH via
# find $BASE_DIR/lsd/jars, but -jxe:$LSD_JXE takes priority over
# -Xbootclasspath:. The jar must also be prepended via -Xbootclasspath/p:
# on VMOPTIONS, right before the $J9 ... -jxe: launch line.
au37x() {
    echo '#!/bin/sh'
    echo 'export BASE_DIR=/mnt/app/eso/hmi/lsd'
    echo 'find $BASE_DIR/lsd/jars -name "*.jar" -o -name "*.zip" | while read jar; do'
    echo '    BOOTCLASSPATH="$BOOTCLASSPATH:$jar"'
    echo 'done'
    echo ''
    for i in $(seq 1 60); do echo "VMOPTIONS=\"\$VMOPTIONS -Dfiller$i=1\""; done
    echo ''
    echo '    $J9 $VMOPTIONS -Xbootclasspath:$BOOTCLASSPATH -jxe:$LSD_DIR/lsd.jxe &'
}

# cycle <name> <lsd.sh source> <expected line after add>
cycle() {
    local name=$1 src=$2 want=$3 app="$T/$1"
    local lsd="$app/eso/hmi/lsd/lsd.sh"
    mkdir -p "$app/eso/hmi/lsd/jars"
    cp "$src" "$lsd"
    cp "$src" "$T/$name.orig"
    echo "fake jar" > "$T/Test.jar"
    run() { LSD_JAR_TEST_APP="$app" sh "$ROOT/scripts/lsd_jar.sh" "$@"; }

    if run loaded Test.jar; then bad "$name: loaded before add"; else ok "$name: not loaded before add"; fi
    nav_before=no; if run loaded NavActiveIgnore.jar; then nav_before=yes; fi
    run add Test.jar "$T/Test.jar" > "$T/out" 2>&1 || { bad "$name: add failed: $(cat "$T/out")"; return; }
    [ -f "$app/eso/hmi/lsd/jars/Test.jar" ] && ok "$name: jar copied" || bad "$name: jar not copied"
    if [ "$name" != au37x ]; then
        [ "$(wc -l < "$lsd")" -eq $(( $(wc -l < "$T/$name.orig") + 1 )) ] && ok "$name: one line added" || bad "$name: line count after add"
    else
        [ "$(wc -l < "$lsd")" -eq "$(wc -l < "$T/$name.orig")" ] && ok "$name: line count unchanged (in-place edit)" || bad "$name: line count changed"
    fi
    grep -qxF "$want" "$lsd" && ok "$name: line is: $want" || bad "$name: expected line missing: $want"
    if [ "$name" = au57x ] || [ "$name" = real ]; then
        a=$(grep -nxF "$want" "$lsd" | cut -d: -f1); j=$(grep -nxF 'BOOTCLASSPATH="$BOOTCLASSPATH:$LSD_DIR/lsd.jxe"' "$lsd" | head -1 | cut -d: -f1)
        [ "$a" -lt "$j" ] && ok "$name: before lsd.jxe (line $a < $j)" || bad "$name: not before lsd.jxe"
    fi
    run loaded Test.jar && ok "$name: loaded after add" || bad "$name: not loaded after add"
    cp "$lsd" "$T/$name.added"
    run add Test.jar "$T/Test.jar" > "$T/out" 2>&1 || bad "$name: second add failed"
    cmp -s "$lsd" "$T/$name.added" && ok "$name: second add changes nothing" || bad "$name: second add changed lsd.sh"
    # A newer build of a loaded jar (the installer calls add again, #24).
    echo "fake jar, newer build" > "$T/Test.jar"
    run add Test.jar "$T/Test.jar" > "$T/out" 2>&1 || bad "$name: add of a newer build failed: $(cat "$T/out")"
    cmp -s "$app/eso/hmi/lsd/jars/Test.jar" "$T/Test.jar" && ok "$name: newer build replaces the loaded jar" || bad "$name: loaded jar not replaced"
    [ -f "$app/eso/hmi/lsd/jars/Test.jar.before_update" ] && ok "$name: previous jar kept as .before_update" || bad "$name: no .before_update"
    cmp -s "$lsd" "$T/$name.added" && ok "$name: replacing the jar leaves lsd.sh alone" || bad "$name: replacing the jar changed lsd.sh"
    nav_after=no; if run loaded NavActiveIgnore.jar; then nav_after=yes; fi
    [ "$nav_after" = "$nav_before" ] && ok "$name: NavActiveIgnore unaffected (loaded: $nav_after)" || bad "$name: NavActiveIgnore changed from $nav_before to $nav_after"
    run remove Test.jar > "$T/out" 2>&1 || { bad "$name: remove failed: $(cat "$T/out")"; return; }
    cmp -s "$lsd" "$T/$name.orig" && ok "$name: remove restores the original byte for byte" || bad "$name: lsd.sh differs from the original after remove"
    if run loaded Test.jar; then bad "$name: loaded after remove"; else ok "$name: not loaded after remove"; fi
    [ -f "$lsd.before_Test" ] && ok "$name: backup lsd.sh.before_Test kept" || bad "$name: no backup"
}

au57x > "$T/au57x.sh"; vw > "$T/vw.sh"
cycle au57x "$T/au57x.sh" 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/Test.jar"'
cycle vw "$T/vw.sh" 'BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/Test.jar"'
au37x > "$T/au37x.sh"
# On the real car, LSD_DIR=/mnt/app/eso/hmi/lsd so this becomes:
#   $J9 $VMOPTIONS -Xbootclasspath:$BOOTCLASSPATH -Xbootclasspath/p:/mnt/app/eso/hmi/lsd/jars/AAcoverart_hook.jar -jxe:$LSD_JXE &
# NOT -Xbootclasspath/p: on VMOPTIONS before $J9 (which -Xbootclasspath:$BOOTCLASSPATH would overwrite).
want37x="    \$J9 \$VMOPTIONS -Xbootclasspath:\$BOOTCLASSPATH -Xbootclasspath/p:$T/au37x/eso/hmi/lsd/jars/Test.jar -jxe:\$LSD_DIR/lsd.jxe &"
want37x_upgrade="    \$J9 \$VMOPTIONS -Xbootclasspath:\$BOOTCLASSPATH -Xbootclasspath/p:$T/au37x-upgrade/eso/hmi/lsd/jars/Test.jar -jxe:\$LSD_DIR/lsd.jxe &"
# The prepend is only for the cover-art jar; Test.jar stands in for it here.
export LSD_JAR_TEST_PREPEND=Test.jar
cycle au37x "$T/au37x.sh" "$want37x"

# Upgrade case: jar already exists in jars/ with same byte size, but lsd.sh
# does NOT have the BOOTPREPEND line. add must still fix lsd.sh in place.
app="$T/au37x-upgrade"
lsd="$app/eso/hmi/lsd/lsd.sh"
mkdir -p "$app/eso/hmi/lsd/jars"
cp "$T/au37x.sh" "$lsd"
echo "fake jar" > "$T/au37x-upgrade/eso/hmi/lsd/jars/Test.jar"
run() { LSD_JAR_TEST_APP="$app" sh "$ROOT/scripts/lsd_jar.sh" "$@"; }
if run loaded Test.jar; then bad "upgrade: loaded before add"; else ok "upgrade: not loaded before add"; fi
run add Test.jar "$T/Test.jar" > "$T/out" 2>&1 || { bad "upgrade: add failed: $(cat "$T/out")"; }
grep -qxF "$want37x_upgrade" "$lsd" && ok "upgrade: BPCP line added to lsd.sh" || bad "upgrade: BPCP line missing from lsd.sh"
run loaded Test.jar && ok "upgrade: loaded after add" || bad "upgrade: not loaded after add"
run remove Test.jar > "$T/out" 2>&1 || { bad "upgrade: remove failed: $(cat "$T/out")"; }
cmp -s "$lsd" "$T/au37x.sh" && ok "upgrade: remove restores original lsd.sh" || bad "upgrade: lsd.sh differs after remove"
if run loaded Test.jar; then bad "upgrade: loaded after remove"; else ok "upgrade: not loaded after remove"; fi
[ -f "$lsd.before_Test" ] && ok "upgrade: backup lsd.sh.before_Test kept" || bad "upgrade: no backup"

# Any other jar on AU37x (NavActiveIgnore, added by default on P5089) is only
# copied into jars/: lsd.sh must stay byte for byte as it was.
app="$T/au37x-other"
lsd="$app/eso/hmi/lsd/lsd.sh"
mkdir -p "$app/eso/hmi/lsd/jars"
cp "$T/au37x.sh" "$lsd"
run() { LSD_JAR_TEST_APP="$app" sh "$ROOT/scripts/lsd_jar.sh" "$@"; }
run add NavActiveIgnore.jar "$T/Test.jar" > "$T/out" 2>&1 || bad "au37x other jar: add failed: $(cat "$T/out")"
[ -f "$app/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && ok "au37x other jar: copied to jars/" || bad "au37x other jar: not copied"
cmp -s "$lsd" "$T/au37x.sh" && ok "au37x other jar: lsd.sh not edited" || bad "au37x other jar: lsd.sh was edited"
run remove NavActiveIgnore.jar > "$T/out" 2>&1 || bad "au37x other jar: remove failed: $(cat "$T/out")"
cmp -s "$lsd" "$T/au37x.sh" && ok "au37x other jar: lsd.sh still the same after remove" || bad "au37x other jar: lsd.sh changed by remove"
unset LSD_JAR_TEST_PREPEND

for real in "$@"; do
    cycle real "$real" 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/Test.jar"'
done
[ "$FAILS" -eq 0 ] && echo "LSD_JAR_TEST_OK" || { echo "LSD_JAR_TEST_FAILED ($FAILS)"; exit 1; }
