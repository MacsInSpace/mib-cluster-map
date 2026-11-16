#!/bin/sh
# Static guards for faults that reached a release once. Each check names the
# report it came from. Run from anywhere: sh tests/regression_guards.sh
# build_local.sh runs it before it packs a card. docs/Development.md,
# "Settled parts", says when a guard may be changed.
ROOT=`dirname "$0"`/..
cd "$ROOT" || exit 2
FAIL=0
bad() { echo "GUARD FAILED: $*"; FAIL=1; }

# 1. #101: the installer wrote GAL_DUALSCREEN_ENABLE=1 into gal's start-up
#    whatever the settings said, and the start-up value beats the settings
#    file, so GAL_DUALSCREEN_ENABLE=0 did nothing up to v1.2.5.
#    The injected value must come from the settings.
grep -n '^INJECTION=' scripts/enable_hook.sh | grep -q 'GAL_DUALSCREEN_ENABLE=\$HOOK_ENABLE' ||
    bad "enable_hook.sh: INJECTION must carry GAL_DUALSCREEN_ENABLE=\$HOOK_ENABLE (#101)"
grep -n 'GAL_DUALSCREEN_ENABLE=1\\"' scripts/enable_hook.sh | grep -v '^[0-9]*:[ 	]*#' | grep -q . &&
    bad "enable_hook.sh: a fixed GAL_DUALSCREEN_ENABLE=1 is written into gal's start-up (#101)"

# 2. #109: paths with /fs/sda0 baked in broke the green menu after an install
#    from USB or the second SD slot. The card is not always /fs/sda0. Every
#    mention is counted in tests/sda0.allow: a new one fails here until it is
#    looked at (a fallback after the real card path is fine; the only path is
#    not) and the count is changed on purpose.
NOW=`grep -rc '/fs/sda0' scripts greenmenu config src player 2>/dev/null |
     grep -v '/thirdparty/' | grep -v ':0$' | sort`
WANT=`grep -v '^#' tests/sda0.allow | grep . | sort`
if [ "$NOW" != "$WANT" ]; then
    bad "/fs/sda0 mentions differ from tests/sda0.allow (#109). Now:"
    echo "$NOW"
fi
# The menu file keeps /fs/sda0 only because every menu script rewrites it to
# the card it ran from (common.sh); that call has to stay.
grep -q '^menu_follow_card$' greenmenu/GEM/common.sh ||
    bad "greenmenu/GEM/common.sh no longer calls menu_follow_card (#109)"

# 3. v1.2.0: the installer runs under set -eu on the unit. A test harness
#    without it let a release through that stopped on an unset variable.
for f in scripts/enable_hook.sh scripts/disable_hook.sh; do
    grep -q '^set -eu' "$f" || bad "$f does not start with set -eu any more"
done

# 4. #85: a change for one car switched the picture crop on for every car.
#    Features ship off: every 0/1 feature switch in the shipped settings that
#    is active must be at its documented default.
for k in CLUSTERMAP_FULL_FRAME CLUSTERMAP_ADD_NAVIGNORE GAL_FIX_STREAM_TIMING GAL_PLAYER_STATS; do
    v=`sed -n "s/^$k=\(.*\)$/\1/p" config/gal_dualscreen.conf | tail -1`
    [ -z "$v" ] || [ "$v" = 0 ] || bad "config/gal_dualscreen.conf ships $k=$v; it has to ship 0"
done
for k in GAL_PLAYER_REASSERT CLUSTERMAP_CARPLAY_TRIAL GAL_PROFILE_TRIAL CLUSTERMAP_KEEP_SETTINGS; do
    grep -q "^$k=" config/gal_dualscreen.conf && bad "config/gal_dualscreen.conf ships an active $k line"
done
[ "`sed -n 's/^GAL_PLAYER_DECODER=//p' config/gal_dualscreen.conf | tail -1`" = sw ] ||
    bad "config/gal_dualscreen.conf must ship GAL_PLAYER_DECODER=sw"

[ $FAIL = 0 ] && echo "regression guards ok"
exit $FAIL
