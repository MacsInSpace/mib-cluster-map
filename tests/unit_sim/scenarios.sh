# Runs inside the simulator image, after make_unit.sh. Drives the card the way
# a unit does and prints one "RESULT <name> <PASS|FAIL> <detail>" line per
# check, plus "CODE <script> <exit code>" for every green menu script.
# /card = the card contents (read-only), /simtools = harness-only tools.
# No set -e here: every check must run.
T=/simtools
CARD=/fs/sda0; PKG=$CARD/ClusterMap
sum() { awk -v f="$2" '$2 == f { print $1 }' "$1"; }
res() { echo "RESULT $1 $2 $3"; }
snap() { find /mnt/app /mnt/system -type f | $T/sort | while read f; do $T/md5sum "$f"; done > "$1"; }
# Messages only the shell or a missing program prints.
shell_noise() {
    grep -n -e '\[[0-9][0-9]*\]: ' -e 'parameter not set' -e 'syntax error' -e 'bad substitution' \
         -e 'cannot execute' -e 'bad number' -e 'is not an identifier' "$@" 2>/dev/null
}
run_update() {   # $1 = name; leaves update_result.txt
    PATH=/proc/boot:$PATH sh $PKG/final/update_run.sh $CARD 32 /net/mmx.mibhigh.net/fs/sda0 > /tmp/$1.out 2>&1
    echo $? > /tmp/$1.code
    cp $PKG/update_result.txt /tmp/$1.result 2>/dev/null || : > /tmp/$1.result
    if N=`shell_noise /tmp/$1.out /tmp/$1.result`; then res "$1.shell" FAIL "`echo "$N" | head -3`"; else res "$1.shell" PASS -; fi
}
expect() {   # $1 name, $2 marker
    if grep -q "$2" /tmp/$1.result; then res "$1" PASS "$2"
    else res "$1" FAIL "no $2; last lines: `grep -v '^$' /tmp/$1.result | tail -3`"; fi
}

mkdir -p $CARD && cp -R /card/. $CARD/
rm -f $PKG/update_result*.txt $PKG/logs/* 2>/dev/null
# The card's helpers are ARM QNX programs; the host build stands in.
if [ -x /sim/profile_check ]; then cp /sim/profile_check $PKG/profile_check; fi
[ -z "${CONF_EDIT:-}" ] || for kv in $CONF_EDIT; do
    sed "s|^#*${kv%%=*}=.*|$kv|" $PKG/gal_dualscreen.conf > /tmp/conf.new && cp /tmp/conf.new $PKG/gal_dualscreen.conf
    grep -q "^$kv\$" $PKG/gal_dualscreen.conf || echo "$kv" >> $PKG/gal_dualscreen.conf
done
snap /tmp/snap0
mkdir -p /out/before /out/after
cp /mnt/app/eso/hmi/lsd/lsd.sh /mnt/system/etc/eso/production/smartphone_integrator.json /out/before/

# 1. collect only: must change nothing on the unit
: > "$PKG/COLLECT.txt"; run_update collect; rm -f "$PKG/COLLECT.txt"
snap /tmp/snapc
if $T/cmp -s /tmp/snap0 /tmp/snapc; then res collect.untouched PASS -; else res collect.untouched FAIL "unit files changed"; fi

# 2. fresh install
: > $CARD/Swdlautorun.txt
run_update install
if [ -f /unit/expect_refuse ]; then
    # A train the package does not support: a clear refusal, nothing changed.
    expect install "NOT SUPPORTED"
    snap /tmp/snap1
    if $T/cmp -s /tmp/snap0 /tmp/snap1; then res refuse.untouched PASS -; else res refuse.untouched FAIL "`$T/diff /tmp/snap0 /tmp/snap1 | grep '^[<>]' | $T/cut -c37- | $T/sort -u | head -5`"; fi
    mkdir -p /out && cp /tmp/*.out /tmp/*.result /out/ 2>/dev/null
    echo "SCENARIOS-DONE"; exit 0
fi
expect install CLUSTERMAP_INSTALL_OK
# No warning about something this unit does not have.
if grep -q "older cluster renderer" /tmp/install.result; then res install.no_false_warning FAIL "`grep -m1 'older cluster renderer' /tmp/install.result | cut -c1-90`"; else res install.no_false_warning PASS -; fi
if [ -f $CARD/_Swdlautorun.txt ] && [ ! -f $CARD/Swdlautorun.txt ]; then res install.autorun_off PASS -; else res install.autorun_off FAIL "Swdlautorun.txt still armed"; fi
snap /tmp/snap1

# 3. every file the install added is replaced by the next install (the stale
#    jar of v1.2.7: a loaded file was never refreshed). Backups are meant to
#    stay as first written.
$T/cut -c35- /tmp/snap0 > /tmp/files0
STALE=
for f in `$T/cut -c35- /tmp/snap1`; do
    grep -q -x -F "$f" /tmp/files0 && continue
    # NavActiveIgnore.jar: a loaded one may be the owner's own (M.I.B. toolbox
    # installs the same patch) and is left alone on purpose.
    case "$f" in */NavActiveIgnore.jar|*/.aacluster_*|*.original|*.before_*|*.owner.conf|*.bak|*backup*) continue ;; esac
    echo stale-test-junk >> "$f"; STALE="$STALE $f"
done
run_update reinstall; expect reinstall CLUSTERMAP_INSTALL_OK
snap /tmp/snap2
BAD=
for f in $STALE; do
    a=`sum /tmp/snap1 "$f"`; b=`sum /tmp/snap2 "$f"`
    [ "$a" = "$b" ] || BAD="$BAD ${f##*/}"
done
if [ -z "$BAD" ]; then res reinstall.refreshes_files PASS "`echo $STALE | wc -w` files"; else res reinstall.refreshes_files FAIL "kept the old copy:$BAD"; fi
# and a plain second install changes nothing more
run_update again; expect again CLUSTERMAP_INSTALL_OK
snap /tmp/snap3
if $T/cmp -s /tmp/snap2 /tmp/snap3; then res again.idempotent PASS -; else res again.idempotent FAIL "`$T/diff /tmp/snap2 /tmp/snap3 | grep '^[<>]' | $T/cut -c37- | $T/sort -u | head -5`"; fi

# 4. uninstall puts every original file back
: > "$PKG/UNINSTALL.txt"; run_update uninstall; rm -f "$PKG/UNINSTALL.txt"
if grep -q -i "FAILED" /tmp/uninstall.result; then res uninstall FAIL "`grep -i FAILED /tmp/uninstall.result | head -2`"; else res uninstall PASS -; fi
snap /tmp/snap4
cp /mnt/app/eso/hmi/lsd/lsd.sh /mnt/system/etc/eso/production/smartphone_integrator.json /out/after/
BAD=
for f in `$T/cut -c35- /tmp/snap0`; do
    a=`sum /tmp/snap0 "$f"`; b=`sum /tmp/snap4 "$f"`
    # Our own arrows jars, loaded by an earlier release: an install updates
    # them (the stale-jar fix) and an uninstall leaves the newer copy loaded.
    case "$f" in */jars/VCAndroidAuto*.jar) [ -n "$b" ] && continue ;; esac
    [ "$a" = "$b" ] || BAD="$BAD $f"
done
if [ -z "$BAD" ]; then res uninstall.restores PASS -; else res uninstall.restores FAIL "differs from before install:$BAD"; fi
$T/cut -c35- /tmp/snap4 > /tmp/files4
LEFT=`grep -v -x -F -f /tmp/files0 /tmp/files4 | $T/tr '\n' ' '`
echo "LEFT ${LEFT:-nothing}"
# and an install after an uninstall
run_update back; expect back CLUSTERMAP_INSTALL_OK
# 5. the green menu scripts, as the menu starts them
for s in status opt_hw_on opt_hw_off opt_keepmap_on opt_keepmap_off opt_map_off opt_map_on opt_stats_on opt_stats_off \
         opt_theme_dark opt_theme_light opt_theme_auto full_frame_on full_frame_off full_frame_720p full_frame_1080p \
         switch_to_turn_by_turn savelogs collect_for_porting status; do
    [ -f $PKG/GEM/$s.sh ] || { res gem.$s FAIL missing; continue; }
    sh $PKG/GEM/$s.sh > /tmp/gem_$s.out 2>&1; c=$?
    echo "CODE $s $c"
    if N=`shell_noise /tmp/gem_$s.out`; then res gem.$s.shell FAIL "`echo "$N" | head -2`"; fi
done
sh $PKG/GEM/install.sh > /tmp/gem_install.out 2>&1; echo "CODE install $?"
if N=`shell_noise /tmp/gem_install.out`; then res gem.install.shell FAIL "`echo "$N" | head -2`"; fi

sh $PKG/GEM/uninstall.sh > /tmp/gem_uninstall.out 2>&1; echo "CODE uninstall $?"
if N=`shell_noise /tmp/gem_uninstall.out`; then res gem.uninstall.shell FAIL "`echo "$N" | head -2`"; fi
mkdir -p /out && cp /tmp/*.out /tmp/*.result /tmp/snap* /tmp/stub_calls.txt /out/ 2>/dev/null
echo "SCENARIOS-DONE"
