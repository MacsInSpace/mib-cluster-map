# Runs inside the simulator image. Lays out a fake head unit from /unit (one
# real unit's files: gal, lsd.sh, smartphone_integrator.json and, when the
# unit has them, libautoreceiver.so, gal.json) and stubs the unit-only
# programs. Stub calls are logged to /tmp/stub_calls.txt.
#   make_unit.sh <train> <cockpit window WxH | none>
set -eu
TRAIN=$1; WIN=${2:-none}
mkdir -p /mnt/app/eso/bin/apps /mnt/app/eso/lib /mnt/app/eso/hmi/lsd/jars /mnt/app/navigation /mnt/app/root \
         /mnt/app/armle/bin /mnt/system/etc/eso/production /net/rcc/dev/shmem /net/mmx.mibhigh.net/fs /fs /ifs
[ -e /eso ] || ln -s /mnt/app/eso /eso
[ -e /etc/eso ] || ln -s /mnt/system/etc/eso /etc/eso
cp /unit/gal /mnt/app/eso/bin/apps/gal
cp /unit/smartphone_integrator.json /mnt/system/etc/eso/production/
if [ -f /unit/gal.json ]; then cp /unit/gal.json /mnt/system/etc/eso/production/; fi
cp /unit/lsd.sh /mnt/app/eso/hmi/lsd/lsd.sh
if [ -f /unit/libautoreceiver.so ]; then cp /unit/libautoreceiver.so /mnt/app/eso/lib/; fi
if [ -f /unit/libairplay.so ]; then cp /unit/libairplay.so /mnt/app/eso/lib/; fi
if [ -f /unit/libautoreceiver_qnx.so.1 ]; then cp /unit/libautoreceiver_qnx.so.1 /mnt/app/eso/lib/; fi
# Every jar lsd.sh starts exists on a real unit; collections do not carry them.
for j in `sed -n 's|.*lsd/jars/\([A-Za-z0-9_.-]*\.jar\).*|\1|p' /unit/lsd.sh`; do
    if [ -f "/unit/jars/$j" ]; then cp "/unit/jars/$j" /mnt/app/eso/hmi/lsd/jars/
    else echo "placeholder for $j, as found on the unit" > "/mnt/app/eso/hmi/lsd/jars/$j"; fi
done
echo "Current train = '$TRAIN'" > /net/rcc/dev/shmem/version.txt
: > /ifs/lsd.jxe
[ -e /net/mmx.mibhigh.net/fs/sda0 ] || ln -s /fs/sda0 /net/mmx.mibhigh.net/fs/sda0
stub() {
    f=$1; n=${f##*/}; shift
    rm -f "$f" "/usr/bin/$n" "/sbin/$n" "/bin/$n"
    { echo '#!/bin/sh'; echo "echo \"$n \$*\" >> /tmp/stub_calls.txt"
      for l in "$@"; do echo "$l"; done; } > "$f"
    chmod 755 "$f"
}
stub /bin/mount 'exit 0'
stub /bin/sync 'exit 0'
stub /bin/slay 'exit 1'
stub /bin/on 'while [ $# -gt 0 ]; do case "$1" in -p|-P) shift; shift ;; -*) shift ;; *) break ;; esac; done; exec "$@"'
stub /bin/pidin 'echo "     pid name"; echo "  12345 /eso/bin/apps/gal"; exit 0'
stub /mnt/app/eso/bin/jsonlint 'echo "[jsonlint]: checking file $2  OK, time=6[ms]"; exit 0'
if [ "$WIN" = none ]; then KOMBI=
else KOMBI="echo \"	33  	window    	${WIN%x*}  x ${WIN#*x} 	2   		DISPLAYABLE_KOMBI_MAP_VIEW\""
fi
stub /mnt/app/eso/bin/apps/dmdt 'case "$1" in gd)' \
    'echo "displaymanager knows 3 displayables:"' \
    'echo "	ID:	type:		size:		#buffer:	dsi-name (guessed using ID & dsi 2.11.27):"' \
    'echo "	16  	window    	1280 x 640 	2   		DISPLAYABLE_HMI"' \
    "$KOMBI" \
    'echo "	3   	window    	800  x 480 	2   		--" ;;' \
    '*) echo "display 4: context 70" ;; esac; exit 0'
echo "fake unit: $TRAIN, cockpit window $WIN"
