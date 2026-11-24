#!/bin/sh
# 5 GHz hotspot test with the car's Wi-Fi client off. Runs detached; output
# to the SD card (ClusterMap/wifi_5g.txt). Every uaputl call is time-limited.
# Steps: wait (up to 4 min) for the client link to go, baseline start on the
# old channel, then channel 36 for 120 s (look for the car's hotspot on the
# phone), then the old channel back.
trap '' HUP
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
SD=
for d in /fs/sd*; do
    if [ -d "$d/ClusterMap" ]; then SD=$d; break; fi
done
[ -n "$SD" ] || exit 1
mount -uw "$SD" 2>/dev/null
O=$SD/ClusterMap/wifi_5g.txt
hide()
{
    sed -e 's/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F:]*/<mac>/g' \
        -e 's/\([sS][sS][iI][dD][^=]*=\).*/\1 <hidden>/'
}
stamp() { echo; echo "=== $*"; }
# u SECS ARGS...: uaputl on uap0, stopped after SECS.
u()
{
    US=$1; shift
    echo "--- uaputl $*"
    uaputl -i uap0 $* > /tmp/wifi_5g.u 2>&1 &
    UP=$!
    UI=0
    while kill -0 $UP 2>/dev/null; do
        if [ $UI -ge $US ]; then
            kill -9 $UP 2>/dev/null
            echo "(stopped after $US s: no answer)"
            break
        fi
        sleep 1
        UI=`expr $UI + 1`
    done
    wait $UP 2>/dev/null
    hide < /tmp/wifi_5g.u | head -20
}
state()
{
    u 10 sys_cfg_channel_ext
    u 10 sys_cfg_bss_status
    ifconfig uap0 2>&1 | grep -e status -e chan | hide
    ifconfig mlan0 2>&1 | grep -e status | hide
}
{
echo "wifi_5g started"
stamp "0. now"
state
stamp "1. waiting for the car's Wi-Fi client to disconnect (up to 4 min)"
W=0
while ifconfig mlan0 2>/dev/null | grep -q "status: active"; do
    if [ $W -ge 240 ]; then echo "client still connected after 4 min: test runs anyway"; break; fi
    sleep 5
    W=`expr $W + 5`
done
echo "client state after ${W} s:"
ifconfig mlan0 2>&1 | grep -e status
OLD=`uaputl -i uap0 sys_cfg_channel 2>/dev/null | sed -n 's/^Channel *= *\([0-9]*\).*/\1/p' | head -1`
[ -n "$OLD" ] || OLD=11
echo "old channel: $OLD"
stamp "2. baseline: hotspot on channel $OLD"
u 10 bss_stop
u 10 sys_cfg_channel_ext $OLD 0 0
u 20 bss_start
sleep 5
state
stamp "3. hotspot on 5 GHz channel 36 for 120 s: look for it on the phone"
u 10 bss_stop
u 10 sys_cfg_channel_ext 36 1 0
u 20 bss_start
sleep 5
state
sleep 55
stamp "3b. after 60 s"
state
sleep 60
stamp "4. restore channel $OLD"
u 10 bss_stop
u 10 sys_cfg_channel_ext $OLD 0 0
u 20 bss_start
sleep 5
state
stamp "5. Wi-Fi driver log"
sloginfo 2>/dev/null | grep -i -e mrvl -e uap0 -e mlan -e MICRO_AP | hide | tail -40
echo
echo "wifi_5g done"
} > $O 2>&1
rm -f /tmp/wifi_5g.u
sync
