#!/bin/sh
# Compare a car's tool_probe.txt (Save logs, run_logs/N) with the simulator.
#
#   tests/unit_sim/probe_compare.sh <car tool_probe.txt> [train name]
#
# Runs scripts/unit_probe.sh in the simulator and prints every check whose
# exit status or output differs. Each difference is either something the
# simulator must copy (tests/unit_sim/Dockerfile, make_unit.sh) or a rule for
# docs/Unit-shell.md and tools/unit_shell_lint.py. The car's file is kept as
# tests/unit_sim/probes/<train>.txt (no firmware in it: names, sizes, results).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
CAR=$1; TRAIN=${2:-car}
IMG=mib-unit-sim:2
docker image inspect $IMG >/dev/null 2>&1 || docker build -q --platform linux/amd64 -t $IMG "$HERE" >/dev/null
SIM=$ROOT/build/unit_sim/probe_sim.txt; mkdir -p "$(dirname "$SIM")"
docker run --rm --platform linux/amd64 -v "$ROOT/scripts":/s:ro $IMG sh /s/unit_probe.sh > "$SIM" 2>&1
grep -q '^probe_end|' "$CAR" || echo "NOTE: the car's probe did not finish; compared up to where it stopped."
mkdir -p "$HERE/probes"; cp "$CAR" "$HERE/probes/$TRAIN.txt"
awk -F'|' '
    !/\|/ { next }
    FNR == NR { sim[$1] = $0; next }
    $1 in sim { if (sim[$1] != $0) { n++; printf "%s\n   car: %s\n   sim: %s\n", $1, substr($0, length($1) + 2), substr(sim[$1], length($1) + 2) }; delete sim[$1]; next }
    { n++; printf "%s\n   car: %s\n   sim: (not run)\n", $1, substr($0, length($1) + 2) }
    END { for (k in sim) { n++; printf "%s\n   car: (not run)\n   sim: %s\n", k, substr(sim[k], length(k) + 2) }
          printf "%d difference(s)\n", n }' "$SIM" "$CAR"
