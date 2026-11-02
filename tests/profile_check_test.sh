#!/bin/sh
# Host test for tools/profile_check.c and profiles.conf. Pass the gal files you
# hold as arguments (firmware stays out of this repository).
#   tests/profile_check_test.sh path/to/gal ...
set -e
ROOT=`cd "\`dirname "$0"\`/.." && pwd`
OUT=${TMPDIR:-/tmp}/profile_check.$$
cc -Wall -Wextra -I"$ROOT/src" "$ROOT/tools/profile_check.c" "$ROOT/src/profile_table.c" -o "$OUT"
for g in "$@"; do
    echo "== $g"
    "$OUT" "$g" "$ROOT/config/profiles.conf" || true
done
rm -f "$OUT"
