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
[ "`sed -n 's/^CLUSTERMAP_FULL_FRAME=//p' config/gal_dualscreen.conf | tail -1`" = auto ] ||
    bad "config/gal_dualscreen.conf must ship CLUSTERMAP_FULL_FRAME=auto (on only where a make line says fullframe)"
for k in CLUSTERMAP_720P CLUSTERMAP_1080P CLUSTERMAP_ADD_NAVIGNORE GAL_FIX_STREAM_TIMING GAL_PLAYER_STATS; do
    v=`sed -n "s/^$k=\(.*\)$/\1/p" config/gal_dualscreen.conf | tail -1`
    [ -z "$v" ] || [ "$v" = 0 ] || bad "config/gal_dualscreen.conf ships $k=$v; it has to ship 0"
done
for k in GAL_PLAYER_REASSERT CLUSTERMAP_CARPLAY_TRIAL GAL_PROFILE_TRIAL CLUSTERMAP_KEEP_SETTINGS; do
    grep -q "^$k=" config/gal_dualscreen.conf && bad "config/gal_dualscreen.conf ships an active $k line"
done
[ "`sed -n 's/^GAL_PLAYER_DECODER=//p' config/gal_dualscreen.conf | tail -1`" = auto ] ||
    bad "config/gal_dualscreen.conf must ship GAL_PLAYER_DECODER=auto (sw unless the train has hwdecode)"
# hw by default only where a car of that train has run it (Development.md).
[ "`grep '^train ' config/profiles.conf | grep -c ' hwdecode'`" = "`grep -c . tests/hwdecode.allow`" ] ||
    bad "a train gained or lost the hwdecode word: it needs a car test, then a line in tests/hwdecode.allow"
for t in `cat tests/hwdecode.allow`; do
    grep "^train $t " config/profiles.conf | grep -q ' hwdecode' || bad "tests/hwdecode.allow lists $t, which has no hwdecode word"
done
grep -q 'strcmp(val, "hw") == 0' player/opengl_gpu.cc || bad "the player must read anything but hw (auto too) as software"

# 5. Every script the menu names has to exist, and so does whatever those
#    scripts call from the package's scripts folder (a menu entry whose
#    script was never packed says "script not found" in the car).
for f in `sed -n 's|.*"/fs/sda0/ClusterMap/GEM/\([^"]*\)".*|\1|p' greenmenu/cluster-map.esd`; do
    [ -f "greenmenu/GEM/$f" ] || bad "cluster-map.esd names GEM/$f, which does not exist"
done
for f in `sed -n 's|.*"\$PKG/scripts/\([a-z_]*\.sh\)".*|\1|p' greenmenu/GEM/*.sh | sort -u`; do
    grep -q "scripts/$f" build_local.sh || bad "a menu script calls scripts/$f, which build_local.sh does not pack"
done

# 6. Under set -e, a block may not end in "[ test ] && command": when the test
#    is false the block's status is 1, and the unit's ksh (ksh88 behaviour)
#    then stops the script. v1.2.7-golf5/golf6 stopped the install after the
#    window message this way (FULL_FRAME=auto resolving to 0). Write an if.
for f in scripts/*.sh greenmenu/GEM/*.sh lsd_jar.sh; do
    [ -f "$f" ] || continue
    grep -q '^[ 	]*set -e' "$f" || continue
    awk -v f="$f" '
        function blank(s) { return s ~ /^[ \t]*$/ || s ~ /^[ \t]*#/ }
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                s = line[i]
                if (s !~ /^[ \t]*\[ .*\] && / || s ~ /\|\|/ || s ~ /\\$/) continue
                for (j = i + 1; j <= NR && blank(line[j]); j++) ;
                if (line[j] ~ /^[ \t]*(fi|else|elif|done|;;|esac|\})/)
                    print f ":" i ": a block ends in \"[ test ] && ...\" (the unit stops under set -e): use if"
            }
        }' "$f"
done > /tmp/.guard6.$$
if [ -s /tmp/.guard6.$$ ]; then cat /tmp/.guard6.$$ >&2; bad "block ending in [ test ] && ... under set -e"; fi
rm -f /tmp/.guard6.$$

# 7. #62 (v1.2.10): Save logs stopped inside the tool probe on a K3342 and a
#    P3236 (the here-string test hung), so the CarPlay files were never
#    copied. The probes run last and only under the time limit, and the
#    here-string test stays out.
grep -q '^x s_herestring' scripts/unit_probe.sh &&
    bad "unit_probe.sh runs the here-string test again (it hung Save logs, #62)"
for p in unit_probe.sh wireless_probe.sh; do
    grep -n "scripts/$p" scripts/collect_logs.sh | grep -v '^[0-9]*:[ 	]*#' | grep -v -e '-r "' |
        grep -v 'limited ' | grep -q . &&
        bad "collect_logs.sh runs $p without the time limit (#62)"
done
LAST_PROBE=`grep -n 'limited [a-z_]* sh' scripts/collect_logs.sh | tail -1 | cut -d: -f1`
LAST_CP=`grep -n '^[ 	]*cp ' scripts/collect_logs.sh | tail -1 | cut -d: -f1`
if [ -z "$LAST_PROBE" ] || [ -z "$LAST_CP" ] || [ "$LAST_PROBE" -lt "$LAST_CP" ]; then
    bad "collect_logs.sh: the probes must run after the last copy (#62)"
fi

[ $FAIL = 0 ] && echo "regression guards ok"
exit $FAIL
