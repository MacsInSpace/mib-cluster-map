#!/bin/sh
# Install test in a stand-in for the head unit: the unit's own shell version
# (PD KSH v5.2.14), without the commands units lack, against real units'
# files. See docs/Testing.md.
#
#   tests/unit_sim/run.sh <card dir> [train ...]
#
# <card dir> holds ClusterMap/ (dist/sdcard after a build). Units come from
# $UNIT_SIM_UNITS (default ../unit_sim_units next to the repo): one folder per
# train, named as the train, holding gal, lsd.sh, smartphone_integrator.json
# as collected by "to only check compatibility" (porting_<train>). They are
# firmware files and stay out of the repo. Without them the test is skipped.
# Exit 0 all pass, 1 a check failed, 77 skipped.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
CARD=$(cd "$1" && pwd); shift
UNITS=${UNIT_SIM_UNITS:-$ROOT/../unit_sim_units}
IMG=mib-unit-sim:3
[ -d "$UNITS" ] || { echo "unit_sim: no unit files at $UNITS (set UNIT_SIM_UNITS); skipped"; exit 77; }
command -v docker >/dev/null || { echo "unit_sim: docker not found; skipped"; exit 77; }
docker image inspect $IMG >/dev/null 2>&1 || docker build -q --platform linux/amd64 -t $IMG "$HERE" >/dev/null
OUT=${UNIT_SIM_OUT:-$ROOT/build/unit_sim}; mkdir -p "$OUT/sim"
cp "$HERE/make_unit.sh" "$HERE/scenarios.sh" "$OUT/sim/"
# profile_check for the image's own processor
docker run --rm --platform linux/amd64 -v "$ROOT":/work:ro -v "$OUT/sim":/sim $IMG \
    sh -c 'gcc -O1 -I/work/src /work/tools/profile_check.c /work/src/profile_table.c -o /sim/profile_check' 
[ $# -gt 0 ] || set -- $(ls "$UNITS")
windows_for() {
    case "$1" in
        *_SEG*|*_SKG*) echo "1010x376 none" ;;
        *_VW*) echo "800x480 1010x376 none" ;;
        *_AUG22_*|*_AU37x_*) echo "1440x455 none" ;;
        *_AU57x_*) echo "800x298 none" ;;
        *) echo "none" ;;
    esac
}
# One scenario run: train, window, settings edit ("default" or K=V,K=V).
one() {
    train=$1; win=$2; edit=$3; U=$UNITS/$train
    if [ "$edit" = default ]; then e=; tag="$train.$win.default"
    else e=$(echo "$edit" | tr , ' '); tag="$train.$win.$(echo "$edit" | cksum | cut -c1-5)"; fi
    D=$OUT/$tag; rm -rf "$D"; mkdir -p "$D"
    docker run --rm --platform linux/amd64 -v "$U":/unit:ro -v "$CARD":/card:ro -v "$OUT/sim":/sim:ro \
        -v "$D":/out -e CONF_EDIT="$e" $IMG \
        sh -c "sh /sim/make_unit.sh '$train' '$win' && sh /sim/scenarios.sh" > "$D/log.txt" 2>&1 || :
    grep -q SCENARIOS-DONE "$D/log.txt" || echo "RESULT harness FAIL did-not-finish" >> "$D/log.txt"
    grep '^CODE ' "$D/log.txt" | tr '\n' ' ' > "$D/codes.txt"
    { echo "$tag ($edit): $(grep -c '^RESULT .* PASS' "$D/log.txt" || :) pass, $(grep -c '^RESULT .* FAIL' "$D/log.txt" || :) fail"
      grep '^RESULT .* FAIL' "$D/log.txt" | sed 's/^/    /' || :; } > "$D/summary.txt"
}
: > "$OUT/jobs.txt"
for train in "$@"; do
    [ -f "$UNITS/$train/gal" ] || { echo "unit_sim: $train: no gal in $UNITS/$train" >&2; exit 1; }
    for win in ${UNIT_SIM_WINDOWS:-$(windows_for "$train")}; do
        for edit in ${UNIT_SIM_EDITS:-default CLUSTERMAP_TURN_INFO=1,GAL_PLAYER_DECODER=hw,CLUSTERMAP_FULL_FRAME=1}; do
            echo "$train $win $edit" >> "$OUT/jobs.txt"
        done
    done
done
running=0
while read -r train win edit; do
    one "$train" "$win" "$edit" &
    running=$((running+1))
    if [ $running -ge "${UNIT_SIM_JOBS:-6}" ]; then wait; running=0; fi
done < "$OUT/jobs.txt"
wait
: > "$OUT/summary.txt"
while read -r train win edit; do
    if [ "$edit" = default ]; then tag="$train.$win.default"; else tag="$train.$win.$(echo "$edit" | cksum | cut -c1-5)"; fi
    cat "$OUT/$tag/summary.txt" >> "$OUT/summary.txt"
done < "$OUT/jobs.txt"
cat "$OUT/summary.txt"
FAILS=$(grep -c '^    RESULT' "$OUT/summary.txt" || :)
# The green menu scripts' exit codes, as a table that must not change unnoticed.
for d in "$OUT"/*/codes.txt; do echo "$(basename "$(dirname "$d")") $(cat "$d")"; done > "$OUT/codes.txt"
echo "unit_sim: $(wc -l < "$OUT/jobs.txt" | tr -d ' ') runs, $FAILS failed check(s). Details: $OUT"
[ "$FAILS" = 0 ]
