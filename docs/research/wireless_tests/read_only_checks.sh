#!/bin/sh
# Read-only live checks, 2026-11-24 (docs/research/wireless.md).
# Read-only live checks on the unit (pdksh). Nothing is written to the unit
# except under /tmp. Run: ssh root@UNIT 'sh -s' < read_only_checks.sh
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
s() { echo; echo "=== $*"; }

s "1. tools that can search binaries"
for t in strings od hexdump grep awk sed timeout use; do
    w=`command -v $t 2>/dev/null`; echo "$t: ${w:-missing}"
done
grep -q UsbdiTransport /mnt/app/eso/bin/apps/gal && echo "grep gal: yes" || echo "grep gal: no"
grep -a -q UsbdiTransport /mnt/app/eso/bin/apps/gal 2>/dev/null && echo "grep -a gal: yes" || echo "grep -a gal: no"

s "2. dmdt gc (Save logs hung here): 15 s limit"
( cd /eso && LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production ./bin/apps/dmdt gc ) > /tmp/lw_gc.txt 2>&1 &
P=$!; i=0
while kill -0 $P 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=`expr $i + 1`; done
if kill -0 $P 2>/dev/null; then echo "dmdt gc: still running after 15 s (hang), stopped"; kill -9 $P; else echo "dmdt gc: finished in ${i} s"; fi
wc -l < /tmp/lw_gc.txt; rm -f /tmp/lw_gc.txt

s "3. Android Auto: gal, USB stack, how phones are announced"
pidin ar | grep -i -e apps/gal -e io-usb -e smartphone_integrator -e usb | grep -v grep
ls -l /dev/io-usb* /dev/usb* 2>/dev/null | head
ls /pps 2>/dev/null | head -40
ls -R /pps 2>/dev/null | grep -i -e blue -e bt -e phone -e smartphone -e gal -e wlan -e wifi | head -30
pidin ar | grep -i -e ipod -e dio_manager | grep -v grep

s "3b. CarPlay: iPhone driver start line and Wi-Fi switches"
ls -l /etc/iap2* /etc/eso/production/*iap* /mnt/app/armle/etc/*iap* /etc/*ipod* /etc/mm/* 2>/dev/null | head -20
grep -il -e wifi -e wireless -e iap2 /etc/eso/production/*.json /etc/eso/production/*.cfg /etc/eso/production/*.conf 2>/dev/null
grep -i -e wifi -e wireless -e transport /etc/eso/production/dio_manager.json 2>/dev/null | head -20

s "4. Wi-Fi: skipped (SSH runs over the car Wi-Fi)"

s "5. Bluetooth: config and SDP"
ls -l /etc/eso/production/*bt* /etc/eso/production/*bluetooth* /mnt/app/eso/bt* 2>/dev/null
ls /dev | grep -i -e hci -e bt -e mbt -e ser | head
pidin ar | grep -i -e btstack -e bluetooth -e connectionmanager | grep -v grep
sloginfo 2>/dev/null | grep -i -e rfcomm -e "sdp" -e "uuid" | sed -e 's/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F:]*/<mac>/g' | tail -20

s "6. what listens on the network now"
netstat -an 2>/dev/null | grep -i listen | head -30
