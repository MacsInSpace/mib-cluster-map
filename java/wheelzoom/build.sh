#!/bin/bash
# Build ClusterMapWheelZoom.jar: steering-wheel zoom for the CarPlay map on
# the AU57x cockpit (see src/local/clustermap/WheelZoom.java).
#
#   java/wheelzoom/build.sh [output dir]      default: build/ at the repo root
#
# The unit's J9 is a Java 1.2-level VM (J2ME Foundation 1.1): the M.I.B. jars
# that work on this car are version 46 with no StackMapTable, built with IBM's
# javac -source 1.2 -target 1.2, and this jar is built to match.
#
#   IBM_JDK_DIR=<unpacked ibm-java-ws-sdk-pxi3260sr4ifx>   the same compiler
#       as M.I.B. (32-bit x86: run in Docker's i386/debian:bookworm-slim)
#   otherwise: the host JDK's javac --release 8, then version 46 and every
#       StackMapTable removed (tools/StripFrames.java)
# Either way the result is checked: version 46, no StackMapTable, and none of
# StringBuilder, invokedynamic, class literals or boxing, which the unit's
# class library or J9 cannot run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=${1:-"$ROOT/build"}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
command -v javap >/dev/null && command -v jar >/dev/null || {
    echo "ERROR: javap and jar are needed for the wheel-zoom jar (any JDK 8 or newer)"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/classes"
OURS=('de/audi/tghu/navi/app/map/CtxShown$ZoomUpdateDelayTimer.class' 'local/clustermap/WheelZoom.class')

if [ -n "${IBM_JDK_DIR:-}" ]; then
    [ -x "$IBM_JDK_DIR/bin/javac" ] || { echo "ERROR: no javac in IBM_JDK_DIR=$IBM_JDK_DIR"; exit 1; }
    command -v docker >/dev/null || { echo "ERROR: IBM_JDK_DIR needs Docker (the IBM JDK is 32-bit x86)"; exit 1; }
    echo "Compiling with IBM javac -source 1.2 -target 1.2 (i386 container)"
    docker run --rm --network none -u "$(id -u):$(id -g)" \
        -v "$IBM_JDK_DIR:/ibmjdk:ro" -v "$HERE:/src:ro" -v "$T/classes:/out" \
        "${IBM_IMAGE:-i386/debian:bookworm-slim}" bash -c \
        'set -e; find /src/src /src/stubs -name "*.java" | sort > /tmp/srcs
         /ibmjdk/bin/javac -source 1.2 -target 1.2 -nowarn -d /out @/tmp/srcs'
    HOW="IBM javac 1.2 target"
else
    command -v javac >/dev/null || { echo "ERROR: javac is needed (any JDK 8 or newer)"; exit 1; }
    echo "Compiling with the host javac --release 8, then frames stripped to version 46"
    SRCS=()
    while IFS= read -r f; do SRCS+=("$f"); done < <(find "$HERE/src" "$HERE/stubs" -name '*.java' | sort)
    javac --release 8 -nowarn -encoding UTF-8 -d "$T/classes" "${SRCS[@]}"
    for c in "${OURS[@]}"; do
        java --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
            "$ROOT/tools/StripFrames.java" "$T/classes/$c"
    done
    HOW="host javac, frames stripped"
fi

for c in "${OURS[@]}"; do
    f="$T/classes/$c"
    [ -f "$f" ] || { echo "ERROR: $c was not built"; exit 1; }
    v=$(javap -v "$f" | sed -n 's/^ *major version: //p')
    [ "$v" = 46 ] || { echo "ERROR: $c is class version $v, not 46"; exit 1; }
    bad=$(javap -c -p -v "$f" | grep -E 'StackMapTable|StringBuilder|invokedynamic|InvokeDynamic|MethodHandle|ldc[_w]* +#[0-9]+ +// class|java/lang/Integer\.valueOf|java/lang/Boolean\.valueOf|BootstrapMethods' || true)
    [ -z "$bad" ] || { echo "ERROR: $c has something the unit's J9 cannot take:"; echo "$bad" | sort -u; exit 1; }
done

rm -f "$OUT/ClusterMapWheelZoom.jar"
(cd "$T/classes" && jar cf "$OUT/ClusterMapWheelZoom.jar" "${OURS[@]}")
echo "Built $OUT/ClusterMapWheelZoom.jar ($HOW): version 46, no StackMapTable"
unzip -l "$OUT/ClusterMapWheelZoom.jar" | grep '\.class$'
