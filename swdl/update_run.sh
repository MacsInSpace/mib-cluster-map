#!/bin/sh
# Run by final/finalScript.sh on the multimedia processor during the
# software update:
#
#   update_run.sh <card path> <HW> <medium>
#
# Installs the cluster map, or removes it when a file whose name starts with
# UNINSTALL is in the ClusterMap folder on the card, or only collects files
# for a compatibility check (changing nothing) when one starts with COLLECT.
# All output goes to ClusterMap/update_result.txt on the card.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

CARD=$1
PKG=$CARD/ClusterMap
RESULT=$PKG/update_result.txt
# A card used in several cars keeps every earlier result, numbered.
if [ -f "$RESULT" ]; then
    N=1
    while [ -e "$PKG/update_result.$N.txt" ]; do N=`expr $N + 1`; done
    mv "$RESULT" "$PKG/update_result.$N.txt"
fi
# Started by the autorun file? Switch it off again, so the update does not
# start once more when the unit restarts with the card still in.
if [ -f "$CARD/Swdlautorun.txt" ] && mv "$CARD/Swdlautorun.txt" "$CARD/_Swdlautorun.txt"; then
    AUTORUN_NOTE="Autorun: Swdlautorun.txt renamed back to _Swdlautorun.txt (off)."
fi
# A trace in RAM too, in case the card cannot be written: Save logs copies it.
echo "update_run: HW=$2 medium=$3 card=$CARD" > /tmp/clustermap_final.txt

# Any file in the ClusterMap folder whose name starts with UNINSTALL or
# COLLECT, in any letter case and with any extension (Windows hides
# extensions, so the file may really be UNINSTALL.txt.txt), except the
# package's own scripts: collect_logs.sh starts with "collect" too. Only this
# folder is looked at.
MODE=install
for f in "$PKG"/*; do
    [ -f "$f" ] || continue
    case "${f##*/}" in
        *.sh) ;;
        [Uu][Nn][Ii][Nn][Ss][Tt][Aa][Ll][Ll]*) MODE=uninstall ;;
    esac
done
for f in "$PKG"/*; do
    [ -f "$f" ] || continue
    case "${f##*/}" in
        *.sh) ;;
        [Cc][Oo][Ll][Ll][Ee][Cc][Tt]*) MODE=collect ;;
    esac
done

{
    echo "Mode: $MODE (HW=$2 medium=$3 card=$CARD)"
    [ -z "${AUTORUN_NOTE:-}" ] || echo "$AUTORUN_NOTE"
    grep "Current train" /net/rcc/dev/shmem/version.txt 2>/dev/null
    if [ "$MODE" = collect ]; then
        # Look only: the status check and the porting files, nothing installed.
        sh "$PKG/GEM/status.sh"
        echo
        sh "$PKG/GEM/collect_for_porting.sh"
    elif [ "$MODE" = uninstall ]; then
        sh "$PKG/GEM/uninstall.sh"
    else
        sh "$PKG/GEM/install.sh"
    fi
} > "$RESULT" 2>&1

if [ "$MODE" = install ]; then
    if grep -q -e "CLUSTERMAP_INSTALL_OK" -e "CLUSTERMAP_TURN_BY_TURN_OK" "$RESULT"; then
        # Make the green engineering menu reachable (hold MENU > Testmode), so
        # the ClusterMap screen this update copied can be used for status,
        # logs and uninstall. The same switch the MQB Coding MIB2 Toolbox sets
        # when it installs. It is left on at uninstall.
        LD_LIBRARY_PATH=/mnt/app/root/lib-target:/eso/lib:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib \
        IPL_CONFIG_DIR=/etc/eso/production \
            /mnt/app/eso/bin/apps/pc b:0:0xC002000D 1 >> "$RESULT" 2>&1
        echo "Engineering menu enabled: hold MENU > Testmode > Green Developer Menu > ClusterMap" >> "$RESULT"
    elif grep -q "NOT SUPPORTED" "$RESULT"; then
        # Nothing was installed. Gather what a port to this firmware needs, so
        # the owner does not have to do anything else to help.
        echo >> "$RESULT"
        echo "Collecting files for porting instead..." >> "$RESULT"
        sh "$PKG/GEM/collect_for_porting.sh" >> "$RESULT" 2>&1
    fi
fi
echo "update_run: done, mode $MODE" >> /tmp/clustermap_final.txt
sync
