#!/usr/bin/env bash
# Builds AAcoverart_hook.jar: Android Auto cover art, track info and the
# playback timer on the Audi A3 8V cockpit (AU37x, CLUSTERMAP_AU37X_COVER=1).
# By kashavsehra (#195), car-tested on his A3 P5089.
#
# Compiled against stubs/ (the stock members it uses, with their stock
# signatures), so no firmware file is needed: the classes come out
# byte-identical to a build against an Audi lsd.jar. Stubs are never packed:
# on -Xbootclasspath/p: they would shadow the unit's own classes.
#
# Class version 46 for the unit's J9, without StackMapTable. Unlike the other
# jars, class constants (ldc class) are allowed here: J9 took them on Kash's
# car.
#
#   java/androidadio/build.sh [out dir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=${1:-"$ROOT/build"}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
command -v javac >/dev/null && command -v jar >/dev/null && command -v javap >/dev/null || {
    echo "ERROR: javac, jar and javap are needed for the cover-art jar (any JDK 8 or newer)"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/classes"
OURS=('com/mhi2/androidadio/AAJavaBridge.class'
      'com/mhi2/androidadio/AAManeuverProvider.class'
      'com/mhi2/androidadio/AATrackProvider.class'
      'com/mhi2/androidadio/AATrackProvider$1.class'
      'com/mhi2/androidadio/AATrackProvider$2.class'
      'de/audi/app/terminalmode/smartphone/androidauto2/AndroidAuto2ListenerDistributor.class')
SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(find "$HERE/src" "$HERE/stubs" -name '*.java' | sort)
javac --release 8 -nowarn -encoding UTF-8 -d "$T/classes" "${SRCS[@]}"
# Every class the sources make has to be in the list (a new inner class would
# otherwise be left out of the jar and fail on the car).
made=$(cd "$T/classes" && find . -name '*.class' | sed 's|^\./||' | while read -r c; do
    [ -f "$HERE/src/${c%%[.\$]*}.java" ] && echo "$c"; done | sort || true)
want=$(printf '%s\n' "${OURS[@]}" | sort)
[ "$made" = "$want" ] || { echo "ERROR: built classes differ from the list in build.sh:"; diff <(echo "$want") <(echo "$made") || true; exit 1; }
for c in "${OURS[@]}"; do
    java --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
        "$ROOT/tools/StripFrames.java" "$T/classes/$c"
done
for c in "${OURS[@]}"; do
    f="$T/classes/$c"
    v=$(javap -v "$f" | sed -n 's/^ *major version: //p')
    [ "$v" = 46 ] || { echo "ERROR: $c is class version $v, not 46"; exit 1; }
    bad=$(javap -c -p -v "$f" | grep -E 'StackMapTable|StringBuilder|invokedynamic|InvokeDynamic|MethodHandle|java/lang/Integer\.valueOf|java/lang/Boolean\.valueOf|BootstrapMethods' || true)
    [ -z "$bad" ] || { echo "ERROR: $c has something the unit's J9 cannot take:"; echo "$bad" | sort -u; exit 1; }
done
rm -f "$OUT/AAcoverart_hook.jar"
(cd "$T/classes" && jar cf "$OUT/AAcoverart_hook.jar" "${OURS[@]}")
echo "Built $OUT/AAcoverart_hook.jar: version 46, no StackMapTable, no stubs"
unzip -l "$OUT/AAcoverart_hook.jar" | grep '\.class$'
