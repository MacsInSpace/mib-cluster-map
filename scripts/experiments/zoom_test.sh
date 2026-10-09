#!/bin/sh
# Input experiment: which Android Auto input, if any, zooms the cluster map?
#   copy this file into the AAClusterMap folder on the card, then:
#   sh /fs/sda0/AAClusterMap/zoom_test.sh
# Needs GAL_INPUT_INJECT=1 in gal_dualscreen.conf and the phone connected with
# the map on the cluster. Watch the CLUSTER map and the CENTRE screen and note
# the step numbers where something changes.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
export PATH
F=/tmp/gal_inject
# sleep may not be on the unit's PATH; fall back to a counting loop.
if command -v sleep >/dev/null 2>&1; then
    pause() { sleep $1; }
else
    pause() { c=0; lim=`expr $1 \* 15000`; while [ $c -lt $lim ]; do c=`expr $c + 1`; done; }
    echo "(no sleep command found; using a slower counting delay)"
fi
send() {   # send <line> : write one request and wait until the hook has taken it
    echo "$1" > $F
    n=0
    while [ -f $F ] && [ $n -lt 20 ]; do pause 1; n=`expr $n + 1`; done
    [ -f $F ] && { echo "   (not picked up: is GAL_INPUT_INJECT=1 set and the phone connected?)"; rm -f $F; }
}
step() {   # step <number> <description> <line> <repeat>
    echo
    echo "STEP $1: $2"
    i=0
    while [ $i -lt $4 ]; do send "$3"; pause 1; i=`expr $i + 1`; done
    pause 4
}
echo "Watch the cluster map and the centre screen. Each step waits a few seconds."
step 1  "cluster channel, rotary +1, three times"            "c rot 65536 1"     3
step 2  "cluster channel, rotary -1, three times"            "c rot 65536 -1"    3
step 3  "cluster channel, rotary +1 with display id 1"       "c rot 65536 1 1"   3
step 4  "cluster channel, DPAD centre (keycode 23)"          "c key 23"          1
step 5  "cluster channel, DPAD up (19), twice"               "c key 19"          2
step 6  "cluster channel, DPAD down (20), twice"             "c key 20"          2
step 7  "cluster channel, zoom in key (168), twice"          "c key 168"         2
step 8  "cluster channel, zoom out key (169), twice"         "c key 169"         2
step 9  "MAIN channel, rotary +1, three times"               "m rot 65536 1"     3
step 10 "MAIN channel, rotary -1, three times"               "m rot 65536 -1"    3
step 11 "MAIN channel, rotary +1 with display id 1"          "m rot 65536 1 1"   3
step 12 "MAIN channel, DPAD up (19) with display id 1"       "m key 19 1 1"      2
echo
echo "Done. Note which steps changed the cluster or the centre screen,"
echo "then run:  sh /fs/sda0/AAClusterMap/collect_logs.sh"
