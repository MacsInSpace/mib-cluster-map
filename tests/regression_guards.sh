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
[ "`sed -n 's/^CLUSTERMAP_1080P=//p' config/gal_dualscreen.conf | tail -1`" = auto ] ||
    bad "config/gal_dualscreen.conf must ship CLUSTERMAP_1080P=auto (on only where a train says hd1080)"
# 1080p by default only on a train owners drove with it, and with the decoder.
for t in `grep '^train ' config/profiles.conf | grep ' hd1080' | awk '{print $2}'`; do
    grep -qx "$t" tests/hwdecode.allow || bad "$t has hd1080 without a car-tested hwdecode"
done
[ "`grep '^train ' config/profiles.conf | grep ' hd1080' | awk '{print $2}' | sort | tr '\n' ' '`" = "MHI2_ER_AU37x_P5089 MHI2_ER_AU37x_P5153 " ] ||
    bad "a train gained or lost the hd1080 word: it needs car tests (P5089 #125, P5153 #155 so far)"
for k in CLUSTERMAP_720P CLUSTERMAP_ADD_NAVIGNORE GAL_FIX_STREAM_TIMING GAL_PLAYER_STATS; do
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
# #195: the A3 cover art ships off, only on the train it was made for, and
# only its own jar may edit lsd.sh on AU37x (never NavActiveIgnore).
grep -q '^#CLUSTERMAP_AU37X_COVER=1$' config/gal_dualscreen.conf && ! grep -q '^CLUSTERMAP_AU37X_COVER=' config/gal_dualscreen.conf ||
    bad "config/gal_dualscreen.conf must ship CLUSTERMAP_AU37X_COVER commented out"
[ "`grep '^train ' config/profiles.conf | grep ' aacover' | awk '{print $2}'`" = MHI2_ER_AU37x_P5089 ] ||
    bad "aacover is only for MHI2_ER_AU37x_P5089 until another car tests it"
grep -q '^PREPEND_JARS=${LSD_JAR_TEST_PREPEND:-AAcoverart_hook.jar}$' scripts/lsd_jar.sh ||
    bad "lsd_jar.sh may edit an AU37x lsd.sh for the cover-art jar only"
grep -q 'AAcoverart_hook.jar' build_local.sh || bad "build_local.sh does not pack AAcoverart_hook.jar"

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
for p in unit_probe.sh; do
    grep -n "scripts/$p" scripts/collect_logs.sh | grep -v '^[0-9]*:[ 	]*#' | grep -v -e '-r "' |
        grep -v 'limited ' | grep -q . &&
        bad "collect_logs.sh runs $p without the time limit (#62)"
done
LAST_PROBE=`grep -n 'limited [a-z_]* [0-9]* sh' scripts/collect_logs.sh | tail -1 | cut -d: -f1`
LAST_CP=`grep -n '^[ 	]*cp ' scripts/collect_logs.sh | tail -1 | cut -d: -f1`
if [ -z "$LAST_PROBE" ] || [ -z "$LAST_CP" ] || [ "$LAST_PROBE" -lt "$LAST_CP" ]; then
    bad "collect_logs.sh: the probes must run after the last copy (#62)"
fi

# 8. 2026-11-24: "dmdt gc" waited on the display manager for good on a Golf
#    P4521 and Save logs stopped there. dmdt runs only through dmdt_q, under
#    the time limit when sleep is there.
grep -n 'bin/apps/dmdt' scripts/collect_logs.sh | grep -v '^[0-9]*:[ \t]*#' | grep -v 'exec \./bin/apps/dmdt' | grep -q . &&
    bad "collect_logs.sh runs dmdt outside dmdt_q (no time limit)"
grep -q 'limited dmdt_\$c [0-9]* dmdt_q' scripts/collect_logs.sh ||
    bad "collect_logs.sh: dmdt queries are not under the time limit"

# 9. 2026-11-26: the splash put GL_UNPACK_ALIGNMENT back to 4, and CarPlay
#    pictures whose rows are not a multiple of 4 bytes (1212 or 1010 wide)
#    were read sheared, their colour off the map (#201). The player's planes
#    are tightly packed: the alignment must only ever be 1.
grep -n 'GL_UNPACK_ALIGNMENT' player/*.cc player/*.h | grep -v 'GL_UNPACK_ALIGNMENT, 1)' | grep -q . &&
    bad "player sets GL_UNPACK_ALIGNMENT to something other than 1 (#201)"

# 10. 2026-11-26: insets per cockpit view (#183) are opt-in. Shipped active,
#     the A3's view insets would replace every car's.
grep -q '^GAL_SECONDARY_\(LARGE_INSETS\|SPORT_INSETS\|DEFAULT_VIEW\)=' config/gal_dualscreen.conf &&
    bad "config/gal_dualscreen.conf ships an active per-view insets line (opt-in, #183)"

[ $FAIL = 0 ] && echo "regression guards ok"
exit $FAIL
