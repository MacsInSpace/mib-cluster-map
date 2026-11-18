#!/bin/sh
# Add one unit to the simulator's private set from a "compatibility check"
# collection (the porting_<train> folder a card writes).
#   tests/unit_sim/add_unit.sh <porting folder> [train name] [refuse]
# "refuse": this train is not supported; the test expects a clean refusal.
set -eu
SRC=$1; HERE=$(cd "$(dirname "$0")" && pwd)
UNITS=${UNIT_SIM_UNITS:-$HERE/../../../unit_sim_units}
TRAIN=${2:-$(basename "$SRC" | sed 's/^porting_//')}
for f in gal lsd.sh smartphone_integrator.json; do
    [ -f "$SRC/$f" ] || { echo "add_unit: $SRC has no $f" >&2; exit 1; }
done
mkdir -p "$UNITS/$TRAIN"
for f in gal lsd.sh smartphone_integrator.json gal.json libautoreceiver.so libairplay.so; do
    if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$UNITS/$TRAIN/"; fi
done
if [ "${3:-}" = refuse ]; then : > "$UNITS/$TRAIN/expect_refuse"; fi
echo "added $TRAIN"
