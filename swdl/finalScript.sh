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
fi

on -f mmx /bin/mount -ur $LOCAL
echo Done.
touch /tmp/SWDLScript.Result
