#!/bin/bash
# Build Android Auto bridge jars for Audi MIB2 AU37x (MHI2_ER_AU37x_P5089).
#
#   java/androidadio/build.sh [output dir]      default: build/ at the repo root
#
# The unit's J9 is a Java 1.2-level VM: jars must be version 46 with no
# StackMapTable, built with --release 8 then frames stripped.
#
# Depends on lsd.jar from your car's MIB2 (placed in TRANSFER/ by you) as the
# compilation classpath for Audi stock classes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=${1:-"$ROOT/build"}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
command -v javac >/dev/null && command -v jar >/dev/null && command -v javap >/dev/null || {
    echo "ERROR: javac, jar and javap are needed (any JDK 8 or newer)"; exit 1; }

# Find lsd.jar for the stock-Audi compilation classpath
LSD_JAR=""
for d in "$ROOT/TRANSFER" "$ROOT/thirdparty" "$HOME"; do
    for f in "$d"/lsd.jar "$d"/**/lsd.jar; do
        [ -f "$f" ] && LSD_JAR="$f" && break 2
    done
done
if [ -z "$LSD_JAR" ]; then
    echo "ERROR: lsd.jar not found. Copy your car's lsd.jar to TRANSFER/lsd.jar"; exit 1
fi
echo "Using lsd.jar: $LSD_JAR"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/classes"

# Collect source files
SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(find "$HERE/src" "$HERE/stubs" -name '*.java' | sort)

echo "Compiling with host javac --release 8 against lsd.jar..."
javac --release 8 -nowarn -encoding UTF-8 -cp "$LSD_JAR" -d "$T/classes" "${SRCS[@]}"

# Classes that need frame stripping (all our classes)
ALL_CLASSES=()
while IFS= read -r f; do
    rel="${f#$HERE/src/}"
    cls="com/mhi2/androidadio/$(basename "$rel" .java).class"
    ALL_CLASSES+=("$cls")
done < <(find "$HERE/src" -name '*.java' | sort)

# Also strip stub classes that reference Audi APIs
for c in org/osgi/framework/FrameworkUtil.class org/osgi/framework/Bundle.class; do
    ALL_CLASSES+=("$c")
done

echo "Stripping StackMapTable frames to version 46..."
for c in "${ALL_CLASSES[@]}"; do
    f="$T/classes/$c"
    [ -f "$f" ] || continue
    python3 "$ROOT/tools/patch_class.py" "$f" >/dev/null
done

# Verify: version 46, no StackMapTable, no StringBuilder/invokedynamic/boxing
for c in "${ALL_CLASSES[@]}"; do
    f="$T/classes/$c"
    [ -f "$f" ] || continue
    v=$(javap -v "$f" | sed -n 's/^ *major version: //p')
    [ "$v" = 46 ] || { echo "ERROR: $c is class version $v, not 46"; exit 1; }
    bad=$(javap -c -p -v "$f" | grep -E 'StackMapTable|StringBuilder|invokedynamic|InvokeDynamic|MethodHandle|BootstrapMethods' || true)
    [ -z "$bad" ] || { echo "ERROR: $c has something J9 cannot take:"; echo "$bad" | sort -u; exit 1; }
done

# Package into JARs
rm -f "$OUT/AAAndroidAutoTrack.jar" "$OUT/AAAndroidAutoTurns.jar"

# Track/cover classes
TRACK_CLASSES=(
    com/mhi2/androidadio/AATrackProvider.class
    com/mhi2/androidadio/AAJavaBridge.class
)
(cd "$T/classes" && jar cf "$OUT/AAAndroidAutoTrack.jar" "${TRACK_CLASSES[@]}")

# Turn/maneuver classes
TURN_CLASSES=(
    com/mhi2/androidadio/AAManeuverProvider.class
    com/mhi2/androidadio/AAJavaBridge.class
)
(cd "$T/classes" && jar cf "$OUT/AAAndroidAutoTurns.jar" "${TURN_CLASSES[@]}")

echo "Built $OUT/AAAndroidAutoTrack.jar"
echo "Built $OUT/AAAndroidAutoTurns.jar"
unzip -l "$OUT/AAAndroidAutoTrack.jar" | grep '\.class$'
unzip -l "$OUT/AAAndroidAutoTurns.jar" | grep '\.class$'
