#!/bin/bash
# Build ClusterMapGfxKeep.jar: puts the AU57x cockpit's nav tab in its MAP
# view while the CarPlay map is up (see src/local/clustermap/GfxKeep.java).
#
#   java/gfxkeep/build.sh [output dir]      default: build/ at the repo root
#
# The unit's J9 is a Java 1.2-level VM: class version 46, no StackMapTable,
# as ClusterMapWheelZoom.jar (java/wheelzoom/build.sh, same three ways):
#   IBM_JDK_DIR=<unpacked IBM SDK>   IBM javac -source 1.2 -target 1.2 (Docker)
#   a JDK 8 javac                    -source 1.2 -target 1.2 straight away
#   any newer javac                  --release 8, then version 46 and every
#                                    StackMapTable removed (tools/StripFrames.java)
# Either way the result is checked: version 46, no StackMapTable, and none of
# StringBuilder, invokedynamic, class literals or boxing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=${1:-"$ROOT/build"}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
command -v javap >/dev/null && command -v jar >/dev/null || {
    echo "ERROR: javap and jar are needed for the cockpit map view jar (any JDK 8 or newer)"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/classes"
OURS=('de/audi/tghu/navi/app/cluster/UpdateGfxState.class' 'local/clustermap/GfxKeep.class')

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
    SRCS=()
    while IFS= read -r f; do SRCS+=("$f"); done < <(find "$HERE/src" "$HERE/stubs" -name '*.java' | sort)
    if javac -version 2>&1 | grep -q ' 1\.8\.'; then
        echo "Compiling with the host JDK 8 javac -source 1.2 -target 1.2"
        javac -source 1.2 -target 1.2 -nowarn -encoding UTF-8 -d "$T/classes" "${SRCS[@]}" 2>&1 \
            | grep -v -e 'bootstrap class path' -e 'obsolete' -e 'suppress warnings' -e '^[0-9]* warnings*$' || true
        HOW="host JDK 8 javac, 1.2 target"
    else
        echo "Compiling with the host javac --release 8, then frames stripped to version 46"
        javac --release 8 -nowarn -encoding UTF-8 -d "$T/classes" "${SRCS[@]}"
        for c in "${OURS[@]}"; do
            java --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
                "$ROOT/tools/StripFrames.java" "$T/classes/$c"
        done
        HOW="host javac, frames stripped"
    fi
fi

for c in "${OURS[@]}"; do
    f="$T/classes/$c"
    [ -f "$f" ] || { echo "ERROR: $c was not built"; exit 1; }
    v=$(javap -v "$f" | sed -n 's/^ *major version: //p')
    [ "$v" = 46 ] || { echo "ERROR: $c is class version $v, not 46"; exit 1; }
    bad=$(javap -c -p -v "$f" | grep -E 'StackMapTable|StringBuilder|invokedynamic|InvokeDynamic|MethodHandle|ldc[_w]* +#[0-9]+ +// class|java/lang/Integer\.valueOf|java/lang/Boolean\.valueOf|BootstrapMethods' || true)
    [ -z "$bad" ] || { echo "ERROR: $c has something the unit's J9 cannot take:"; echo "$bad" | sort -u; exit 1; }
done

rm -f "$OUT/ClusterMapGfxKeep.jar"
(cd "$T/classes" && jar cf "$OUT/ClusterMapGfxKeep.jar" "${OURS[@]}")
echo "Built $OUT/ClusterMapGfxKeep.jar ($HOW): version 46, no StackMapTable"
unzip -l "$OUT/ClusterMapGfxKeep.jar" | grep '\.class$'
