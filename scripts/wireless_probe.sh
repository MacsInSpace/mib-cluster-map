#!/bin/sh
# Wireless groundwork (Android Auto and CarPlay without a cable): what this
# unit has for it. Save logs runs it on every car, so each model adds what
# its own firmware has.
#
#   wireless_probe.sh <out folder>
#
# Read-only: it reads logs, settings and the stock programs, and asks the
# Wi-Fi and firewall tools to show their state; it changes nothing. Hotspot
# names, passwords and MAC addresses are hidden, as Save logs can end up in
# a public issue.
#
# How wireless projection starts, and so what is looked at here:
#   1. Bluetooth: the phone finds the car's service and opens a serial
#      channel (RFCOMM). btstack, its services, and what the log says.
#   2. The car hands over its hotspot's name and password on that channel.
#      CarPlay: the stock iPhone driver can (ipod-drvr-iap2.so, iap2.cfg).
#   3. The phone joins the hotspot (uap0) and connects to the car over the
#      network. Android Auto wants 5 GHz: the hotspot's channel and band.
#   4. The projection runs over that connection: the firewall on uap0, and
#      gal's transport (USB only in the stock build).
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
OUT=${1:-.}
mkdir -p "$OUT" 2>/dev/null
# hide: MAC addresses, and the value on any line about a network name,
# password or key.
X='[0-9a-fA-F][0-9a-fA-F]'
MAC="$X:$X:$X:$X:$X:$X"
hide()
{
    sed -e "s/$MAC/<mac>/g" \
        -e 's/\([Ss][Ss][Ii][Dd][^=:]*[=:]\).*/\1 <hidden>/' \
        -e 's/\([Ss][Ss][Ii][Dd]\) [^=:< ][^ ]*/\1 <hidden>/g' \
        -e 's/\([Pp][Aa][Ss][Ss][^=:]*[=:]\).*/\1 <hidden>/' \
        -e 's/\([Pp][Ss][Kk][^=:]*[=:]\).*/\1 <hidden>/' \
        -e 's/\([Kk][Ee][Yy][^=:]*[=:]\).*/\1 <hidden>/'
}
# has FILE TEXT: yes or no, for a capability string in a stock program.
has()
{
    if [ ! -f "$1" ]; then echo "$2: (no $1)"; return 0; fi
    if grep -q "$2" "$1" 2>/dev/null; then echo "$2: yes"; else echo "$2: no"; fi
}
size_of()
{
    if [ -f "$1" ]; then echo "$1 `wc -c < "$1" | sed 's/ //g'` bytes"; else echo "$1 not found"; fi
}
SLOG=$OUT/sloginfo.tmp
sloginfo > $SLOG 2>/dev/null

{
    echo "=== tools"
    for t in uaputl pfctl wpa_cli ifconfig tcpdump; do
        P=`command -v $t 2>/dev/null` || P=
        echo "$t: ${P:-not found}"
    done
    echo "=== stock programs (the size tells builds apart)"
    for f in /eso/bin/apps/btstack /eso/bin/apps/bluetooth /eso/bin/apps/gal /eso/lib/libautoreceiver.so \
             /eso/lib/libairplay.so /mnt/app/armle/lib/dll/ipod-drvr-iap2.so /mnt/app/armle/usr/lib/libiap2client.so.1; do
        size_of $f
    done
    echo "=== Bluetooth: what btstack can do (step 1)"
    has /eso/bin/apps/btstack RFCOMM
    has /eso/bin/apps/btstack SDP_ParseAttributes
    has /eso/bin/apps/btstack "Serial Port"
    has /eso/bin/apps/btstack iAP
    # Google's wireless Android Auto service ID; no stock unit has been seen
    # with it, so a yes here would be news.
    has /eso/bin/apps/btstack 4de17a00
    has /eso/bin/apps/bluetooth 4de17a00
    echo "=== CarPlay: the stock Wi-Fi handoff (step 2)"
    has /mnt/app/armle/lib/dll/ipod-drvr-iap2.so RequestAccessoryWiFiConfigurationInformation
    has /mnt/app/armle/lib/dll/ipod-drvr-iap2.so BluetoothiAP2Link
    has /mnt/app/armle/lib/dll/ipod-drvr-iap2.so "Wifi Feature not supported"
    has /eso/lib/libairplay.so IsWiFiNetworkInterface
    echo "=== Android Auto: gal's transport (step 4)"
    has /eso/bin/apps/gal UsbdiTransport
    has /eso/bin/apps/gal TcpTransport
    has /eso/bin/apps/gal SocketTransport
    has /eso/lib/libautoreceiver.so WifiInfoResponse
    has /eso/lib/libautoreceiver.so WifiStartRequest
} > $OUT/capabilities.txt 2>&1

{
    echo "=== Wi-Fi chip and firmware (the log since start-up)"
    grep -e FWVer -e "fw file" -e "sd8" -e MICRO_AP -e "WLAN FW" -e "ConMan WLAN" $SLOG | hide | sed -n 1,40p
    echo "=== hotspot (uap0)"
    ifconfig uap0 2>&1 | hide
    echo "=== Wi-Fi client (mlan0)"
    ifconfig mlan0 2>&1 | hide
    # uaputl is Marvell's hotspot tool. Each command below only reads when it
    # has no values after it. The help comes first, to see this build's list.
    if command -v uaputl >/dev/null 2>&1; then
        echo "=== uaputl (help)"
        uaputl < /dev/null 2>&1 | sed -n 1,80p
        for c in sys_info sys_config sys_cfg_channel sys_cfg_80211d; do
            echo "=== uaputl $c"
            uaputl $c < /dev/null 2>&1 | hide | sed -n 1,80p
        done
    fi
} > $OUT/hotspot.txt 2>&1

{
    echo "=== rules loaded now, for the hotspot (uap0)"
    if command -v pfctl >/dev/null 2>&1; then
        pfctl -sr < /dev/null 2>&1 | grep -e uap0 -e wlan | sed -n 1,80p
    fi
    echo "=== /mnt/system/etc/pf.conf lines for the hotspot"
    grep -n -e wlan_if -e uap0 /mnt/system/etc/pf.conf 2>&1 | sed -n 1,80p
} > $OUT/firewall.txt 2>&1

{
    echo "=== processes"
    pidin ar 2>/dev/null | grep -e btstack -e bluetooth -e connectionmanager -e smartphone_integrator \
        -e wpa_supplicant -e dnsmasq -e mm-ipod -e io-media -e dio_manager -e "apps/gal"
    echo "=== Bluetooth in the log (profiles, serial channels, services)"
    grep -e RFCOMM -e SDP -e "HF:" -e A2DP -e AVRCP -e iAP -e IAP -e SPP -e "Serial Port" \
         -e BNEP -e PBAP -e "MAP:" -e Pairing -e pairing $SLOG | hide | tail -150
} > $OUT/bluetooth.txt 2>&1

# iap2.cfg: the iPhone driver's settings. A [wifi] section would mean this
# unit already hands its hotspot to the iPhone. Lines with names or keys are
# hidden.
if [ -r /mnt/system/etc/mm/iap2.cfg ]; then hide < /mnt/system/etc/mm/iap2.cfg > $OUT/iap2.cfg.txt 2>&1; fi
# The wireless bench test's log, if a test build ran it (branch wireless).
cp /tmp/wireless_bench.log $OUT/ 2>/dev/null
rm -f $SLOG
exit 0
