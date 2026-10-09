#!/bin/sh
# The turn-by-turn arrows jar (adi961's VCAndroidAuto.jar) and the cluster map
# cannot both be active: with the jar loaded, the cluster goes blank when a
# route starts. This script switches the jar on and off through lsd_jar.sh.
#
#   turn_by_turn.sh remove    take its line out (done by the map installer)
#   turn_by_turn.sh restore   put it back, only if "remove" took it out
#   turn_by_turn.sh install   copy the bundled jar if needed and add its line
#
# Reboot afterwards.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
set -eu

HERE=`cd "\`dirname "$0"\`" && pwd`
NAME=VCAndroidAuto.jar
MARKER=/mnt/app/eso/hmi/lsd/.aacluster_tbt_removed
mark() { mount -uw /mnt/app 2>/dev/null || true; if [ "$1" = set ]; then : > "$MARKER"; else rm -f "$MARKER"; fi; mount -ur /mnt/app 2>/dev/null || true; }

case "${1:-}" in
    remove)
        if sh "$HERE/lsd_jar.sh" loaded $NAME; then
            sh "$HERE/lsd_jar.sh" remove $NAME
            mark set
        else
            echo "$NAME is not loaded; nothing to remove."
        fi ;;
    restore)
        if [ -f "$MARKER" ]; then
            sh "$HERE/lsd_jar.sh" add $NAME "$HERE/thirdparty/$NAME"
            mark clear
        else
            echo "The installer did not remove a turn-by-turn jar on this unit; nothing to restore."
        fi ;;
    install)
        if grep -q 'libgal_hook.so' /mnt/system/etc/eso/production/smartphone_integrator.json 2>/dev/null; then
            echo "The cluster map is installed. Uninstall it first; the two cannot run together." >&2; exit 1
        fi
        sh "$HERE/lsd_jar.sh" add $NAME "$HERE/thirdparty/$NAME"
        mark clear ;;
    *) echo "usage: $0 remove|restore|install" >&2; exit 2 ;;
esac
echo "Reboot the unit to apply."
