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
    [ "$(wc -l < "$lsd")" -eq $(( $(wc -l < "$T/$name.orig") + 1 )) ] && ok "$name: one line added" || bad "$name: line count after add"
    grep -qxF "$want" "$lsd" && ok "$name: line is: $want" || bad "$name: expected line missing: $want"
    if [ "$name" = au57x ] || [ "$name" = real ]; then
        a=$(grep -nxF "$want" "$lsd" | cut -d: -f1); j=$(grep -nxF 'BOOTCLASSPATH="$BOOTCLASSPATH:$LSD_DIR/lsd.jxe"' "$lsd" | head -1 | cut -d: -f1)
        [ "$a" -lt "$j" ] && ok "$name: before lsd.jxe (line $a < $j)" || bad "$name: not before lsd.jxe"
    fi
    run loaded Test.jar && ok "$name: loaded after add" || bad "$name: not loaded after add"
    cp "$lsd" "$T/$name.added"
    run add Test.jar "$T/Test.jar" > "$T/out" 2>&1 || bad "$name: second add failed"
    cmp -s "$lsd" "$T/$name.added" && ok "$name: second add changes nothing" || bad "$name: second add changed lsd.sh"
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
for real in "$@"; do
    cycle real "$real" 'BOOTCLASSPATH="$BOOTCLASSPATH:/eso/hmi/lsd/jars/Test.jar"'
done
[ "$FAILS" -eq 0 ] && echo "LSD_JAR_TEST_OK" || { echo "LSD_JAR_TEST_FAILED ($FAILS)"; exit 1; }
