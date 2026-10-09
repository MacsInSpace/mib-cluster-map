#!/bin/ksh
# Final script of the "Android Auto Cluster Map" software update package.
# The unit's update process runs it once, after copying the menu screen.
# It installs the cluster map, or removes it when a file whose name starts with
# UNINSTALL is present in the AAClusterMap folder on the card.
# All output goes to AAClusterMap/update_result.txt on the card.

echo FinalScript for HW ${1} on medium ${2}...

VOLUME="${2}"
if [ -z "$VOLUME" ] || [ ! -d "$VOLUME/AAClusterMap" ]; then
    if [ -d /net/mmx/fs/sda0/AAClusterMap ]; then
        VOLUME=/net/mmx/fs/sda0
    elif [ -d /net/mmx/fs/sdb0/AAClusterMap ]; then
        VOLUME=/net/mmx/fs/sdb0
    else
        echo AAClusterMap folder not found on an SD card.
        touch /tmp/SWDLScript.Result
        exit 0
    fi
fi
# The same card as the multimedia processor sees it.
LOCAL=`echo "$VOLUME" | sed 's|^/net/mmx||'`

on -f mmx /bin/mount -uw $LOCAL
RESULT=$VOLUME/AAClusterMap/update_result.txt

# Any file in the AAClusterMap folder whose name starts with UNINSTALL, in any
# letter case and with any extension (Windows hides extensions, so the file may
# really be UNINSTALL.txt.txt). Only this folder is looked at.
MODE=install
for f in "$VOLUME"/AAClusterMap/UNINSTALL* "$VOLUME"/AAClusterMap/uninstall* "$VOLUME"/AAClusterMap/Uninstall*; do
    [ -f "$f" ] && MODE=uninstall
done

if [ "$MODE" = uninstall ]; then
    echo "Mode: uninstall" > $RESULT
    on -f mmx /bin/sh $LOCAL/AAClusterMap/GEM/uninstall.sh >> $RESULT 2>&1
else
    echo "Mode: install" > $RESULT
    on -f mmx /bin/sh $LOCAL/AAClusterMap/GEM/install.sh >> $RESULT 2>&1
    if grep -q "AACLUSTER_INSTALL_OK" $RESULT; then
        # Make the green engineering menu reachable (hold MENU > Testmode), so
        # the AAClusterMap screen this update copied can be used for status,
        # logs and uninstall. The same switch the MQB Coding MIB2 Toolbox sets
        # when it installs. It is left on at uninstall.
        export LD_LIBRARY_PATH=/mnt/app/root/lib-target:/eso/lib:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib
        export IPL_CONFIG_DIR=/etc/eso/production
        on -f mmx /net/mmx/mnt/app/eso/bin/apps/pc b:0:0xC002000D 1 >> $RESULT 2>&1
        echo "Engineering menu enabled: hold MENU > Testmode > Green Developer Menu > AAClusterMap" >> $RESULT
    elif grep -q "NOT SUPPORTED" $RESULT; then
        # Nothing was installed. Gather what a port to this firmware needs, so
        # the owner does not have to do anything else to help.
        echo >> $RESULT
        echo "Collecting files for porting instead..." >> $RESULT
        on -f mmx /bin/sh $LOCAL/AAClusterMap/GEM/collect_for_porting.sh --small >> $RESULT 2>&1
    fi
fi

on -f mmx /bin/mount -ur $LOCAL
echo Done.
touch /tmp/SWDLScript.Result
