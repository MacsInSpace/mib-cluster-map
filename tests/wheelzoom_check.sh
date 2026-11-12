#!/bin/bash
# Check build/ClusterMapWheelZoom.jar against a converted stock lsd.jar of
# MHI2_ER_AU57x_K3663 (MU1425; lsd.jxe 44688282 bytes) before installing it:
#
#   tests/wheelzoom_check.sh /path/to/MU1425-lsd.jar
#
# Make the lsd.jar from the unit's lsd.jxe (the porting folder has it) with
# jxe2jar. It is a Volkswagen/Harman file: keep it out of the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: $0 <stock lsd.jar>"; exit 2; }
[ -r "$ROOT/build/ClusterMapWheelZoom.jar" ] || "$ROOT/java/wheelzoom/build.sh"
exec java -Xverify:all --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
    "$ROOT/tools/WheelZoomCheck.java" "$ROOT/build/ClusterMapWheelZoom.jar" "$1"
