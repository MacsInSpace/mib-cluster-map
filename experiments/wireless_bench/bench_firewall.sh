#!/bin/sh
# Wireless bench test, TEST BUILD ONLY (experiments/wireless_bench/README.md).
# Lets the laptop on the car's hotspot reach the bench listener (TCP 5288).
#
#   sh <card>/ClusterMap/bench_firewall.sh        (over SSH, after each start-up)
#
# The stock rules block every port on the hotspot's own address that they do
# not name. This loads a copy of them with one more "pass" line, for the
# hotspot's own network only. /mnt/system/etc/pf.conf is not changed, so the
# next start-up has the stock rules again.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
PORT=${1:-5288}
SRC=/mnt/system/etc/pf.conf
TMP=/tmp/pf.wireless_bench.conf
if ! command -v pfctl >/dev/null 2>&1; then echo "no pfctl on this unit"; exit 1; fi
if ! grep -q 'block in quick on $wlan_if from any to ($wlan_if)' $SRC; then
    echo "the hotspot rule this script expects is not in $SRC; nothing changed"
    exit 1
fi
awk -v p="$PORT" '
    index($0, "block in quick on $wlan_if from any to ($wlan_if)") == 1 && !done {
        print "# wireless bench test, loaded by bench_firewall.sh"
        print "pass in quick on $wlan_if proto tcp from ($wlan_if:network) to ($wlan_if) port " p " keep state allow-opts"
        done = 1
    }
    { print }' $SRC > $TMP
if pfctl -nf $TMP; then
    pfctl -f $TMP
    echo "loaded; the rule now in force:"
    pfctl -sr 2>/dev/null | grep "port = $PORT"
else
    echo "the copy did not parse; nothing changed"
fi
rm -f $TMP
