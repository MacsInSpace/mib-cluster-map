#!/bin/ksh
# Final script of the "MIB Cluster Map" software update package.
# The unit's update process runs it once, after copying the menu screen.
#
# It runs on the RCC processor, which has very few programs: only ksh
# builtins, touch and "on" are used here, as in the MIB2 Toolbox's final
# script. Everything else runs on the multimedia processor (MMX), where the
# installer runs, through final/update_run.sh, which also writes
# ClusterMap/update_result.txt on the card.

echo FinalScript for HW ${1} on medium ${2}...

VOLUME="${2}"
if [ -z "$VOLUME" ] || [ ! -d "$VOLUME/ClusterMap" ]; then
    if [ -d /net/mmx/fs/sda0/ClusterMap ]; then
        VOLUME=/net/mmx/fs/sda0
    elif [ -d /net/mmx/fs/sdb0/ClusterMap ]; then
        VOLUME=/net/mmx/fs/sdb0
    else
        echo ClusterMap folder not found on an SD card.
        touch /tmp/SWDLScript.Result
        exit 0
    fi
fi
# The same card as the multimedia processor sees it (ksh, no sed).
LOCAL=${VOLUME#/net/mmx}

# Exactly as the toolbox: make the card writable through its RCC path and
# log there first, so even a failure below leaves a record on the card.
on -f mmx /bin/mount -uw $VOLUME
TRACE=$VOLUME/ClusterMap/final_trace.txt
{
    echo "FinalScript started: HW=${1} medium=${2} card=$VOLUME mmx-path=$LOCAL"
    echo "pwd=`pwd`"
} > $TRACE 2>&1
on -f mmx /bin/sh $LOCAL/ClusterMap/final/update_run.sh $LOCAL "${1}" "${2}" >> $TRACE 2>&1
echo "update_run.sh returned $?" >> $TRACE 2>&1
on -f mmx /bin/mount -ur $VOLUME

echo Done.
touch /tmp/SWDLScript.Result
