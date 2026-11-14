#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/lib_cluster_frame.sh"

frame_geometry 1010 376 0
[ "$FRAME_W" = 800 ] && [ "$FRAME_H" = 480 ] &&
    [ "$MARGIN_W" = 0 ] && [ "$MARGIN_H" = 182 ]
frame_geometry 1010 376 1
[ "$FRAME_MODE" = full-frame ] && [ "$MARGIN_W" = 0 ] && [ "$MARGIN_H" = 0 ]
[ "$PIXEL_ASPECT_E4" = 16117 ]
frame_geometry 1010 376 0 1 0
[ "$FRAME_W" = 1280 ] && [ "$FRAME_H" = 720 ] &&
    [ "$MARGIN_W" = 270 ] && [ "$MARGIN_H" = 344 ]
frame_geometry 1440 455 0 0 1
[ "$FRAME_W" = 1920 ] && [ "$FRAME_H" = 1080 ] &&
    [ "$MARGIN_W" = 480 ] && [ "$MARGIN_H" = 625 ]
[ $((FRAME_H - MARGIN_H)) -eq 455 ]

TMP=${TMPDIR:-/tmp}/cluster-frame-test.$$
TEST_BIN=${TMP}.hd-insets
trap 'rm -f "$TMP" "$TMP.new" "$TEST_BIN"' 0 1 2 15
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
    "$ROOT/tests/hd_frame_insets_test.c" -o "$TEST_BIN"
"$TEST_BIN"
{
    echo "GAL_PLAYER_WINDOW=800x480"
    echo "GAL_SECONDARY_WIDTH=800"
    echo "GAL_SECONDARY_HEIGHT=480"
    echo "CLUSTERMAP_1080P=0"
} > "$TMP"
frame_write_conf "$TMP" 1440 455 1 0 1
grep -q '^GAL_PLAYER_WINDOW=1440x455$' "$TMP"
grep -q '^GAL_SECONDARY_WIDTH=1920$' "$TMP"
grep -q '^GAL_SECONDARY_HEIGHT=1080$' "$TMP"
grep -q '^GAL_SECONDARY_MARGINS=480x625$' "$TMP"
grep -q '^CLUSTERMAP_FULL_FRAME=1$' "$TMP"
grep -q '^CLUSTERMAP_720P=0$' "$TMP"
grep -q '^CLUSTERMAP_1080P=1$' "$TMP"
frame_write_conf "$TMP" 1010 376 0 1 0
grep -q '^GAL_SECONDARY_WIDTH=1280$' "$TMP"
grep -q '^GAL_SECONDARY_HEIGHT=720$' "$TMP"
grep -q '^GAL_SECONDARY_MARGINS=270x344$' "$TMP"
grep -q '^CLUSTERMAP_720P=1$' "$TMP"
grep -q '^CLUSTERMAP_1080P=0$' "$TMP"
echo "cluster frame geometry ok"
