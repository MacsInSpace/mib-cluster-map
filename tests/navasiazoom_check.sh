#!/bin/bash
# Check build/ClusterMapNavAsiaZoom.jar against a converted stock lsd.jar of
# MHI2_CN_AU57x_K1006_2 (lsd.jxe 43229093 bytes) before installing it:
#
#   tests/navasiazoom_check.sh /path/to/K1006-lsd.jar
#
# 1. tools/WheelZoomCheck.java: the replaced listener has the stock shape,
#    every call resolves to something public, and the classes verify.
# 2. tools/bytecode_diff.py: every method of the listener compiles to the
#    stock code, except increment and decrement (the NavAsiaZoom call).
#
# Make the lsd.jar from the unit's lsd.jxe (the porting folder has it) with
# jxe2jar. It is a Volkswagen/Harman file: keep it out of the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: $0 <stock lsd.jar>"; exit 2; }
[ -r "$ROOT/build/ClusterMapNavAsiaZoom.jar" ] || "$ROOT/java/navasiazoom/build.sh"
LISTENER=de/audi/tghu/navasia/app/NavAsiaModelListener
java -Xverify:all --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
    "$ROOT/tools/WheelZoomCheck.java" "$ROOT/build/ClusterMapNavAsiaZoom.jar" "$1" \
    $LISTENER local/clustermap/NavAsiaZoom local/clustermap/WheelZoom
python3 "$ROOT/tools/bytecode_diff.py" "$ROOT/build/ClusterMapNavAsiaZoom.jar" "$1" $LISTENER increment decrement
