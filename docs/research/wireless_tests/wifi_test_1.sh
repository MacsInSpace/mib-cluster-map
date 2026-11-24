#!/bin/sh
# First Wi-Fi test, 2026-11-24 (docs/research/wireless.md). Kept as run;
# its 5 GHz step ran with the car's Wi-Fi client connected, a confound that
# wifi_test_5ghz.sh removes.
# Wi-Fi tests that may drop the car's Wi-Fi for a while. Runs detached and
# writes to the SD card, so a dropped SSH link loses nothing.
# Part A reads only (plus one client scan). Part B tries the hotspot on 5 GHz
# channel 36 for 30 s and always puts the old channel back.
trap '' HUP
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
SD=
for d in /fs/sd*; do
    if [ -d "$d/ClusterMap" ]; then SD=$d; break; fi
done
[ -n "$SD" ] || exit 1
mount -uw "$SD" 2>/dev/null
O=$SD/ClusterMap/wifi_live.txt
hide()
{
    sed -e 's/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F:]*/<mac>/g' \
        -e 's/\([sS][sS][iI][dD][^=]*=\).*/\1 <hidden>/' \
        -e 's/\([pP][sS][kK][^=]*=\).*/\1 <hidden>/' \
        -e 's/\([pP]assphrase[^=]*=\).*/\1 <hidden>/'
}
s() { echo; echo "=== $*"; }
u() { echo "--- uaputl $*"; uaputl -i uap0 $* 2>&1 | hide | head -40; }
{
echo "wifi_live started"
s "A1. hotspot now"
u sys_info
u sys_cfg_channel
u sys_cfg_channel_ext
# WARNING: on the Golf P4521 the next line (a read) made the Wi-Fi driver
# fail and reset the chip; the hotspot stayed off until an MMI restart.
u sys_cfg_scan_channels
u sys_cfg_80211d
u sys_cfg_bss_status
u sta_list
ifconfig uap0 2>&1 | hide
ifconfig mlan0 2>&1 | hide
s "A2. client (mlan0)"
wpa_cli -i mlan0 status 2>&1 | hide
grep -i -e country -e freq -e band -e ctrl_interface /ramdisk/wpa_supplicant.conf 2>/dev/null
s "A3. client scan: which bands the radio hears (freq signal flags)"
wpa_cli -i mlan0 scan 2>&1
sleep 6
wpa_cli -i mlan0 scan_results 2>&1 | awk 'NR > 1 { print $2, $3, $4 }' | sort -n | head -40
s "A4. stock Wi-Fi settings files"
for f in /etc/eso/production/*wlan* /etc/eso/production/*conman* /etc/eso/production/*connection* /etc/*wlan* /etc/*uap*; do
    [ -f "$f" ] || continue
    echo "--- $f"
    grep -i -e channel -e band -e country -e 5g -e 80211 -e hostap -e "uap" "$f" 2>/dev/null | hide | head -20
done

s "B. hotspot on 5 GHz channel 36 for 30 s"
OLD=`uaputl -i uap0 sys_cfg_channel 2>/dev/null | sed -n 's/^Channel *= *\([0-9]*\).*/\1/p' | head -1`
[ -n "$OLD" ] || OLD=11
echo "old channel: $OLD"
u bss_stop
u sys_cfg_channel_ext 36 1 0
u bss_start
sleep 5
u sys_cfg_channel_ext
u sys_cfg_bss_status
ifconfig uap0 2>&1 | grep -e status -e chan | hide
sleep 25
u sys_cfg_bss_status
echo "--- restore channel $OLD"
u bss_stop
u sys_cfg_channel_ext $OLD 0 0
u bss_start
sleep 3
u sys_cfg_channel
u sys_cfg_bss_status
s "C. Wi-Fi driver log during the test"
sloginfo 2>/dev/null | grep -i -e mrvl -e uap -e wlan -e mlan -e 80211 | hide | tail -40
echo
echo "wifi_live done"
} > $O 2>&1
sync
