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

on -f mmx /bin/mount -uw $LOCAL
on -f mmx /bin/sh $LOCAL/ClusterMap/final/update_run.sh $LOCAL "${1}" "${2}"
on -f mmx /bin/mount -ur $LOCAL

echo Done.
touch /tmp/SWDLScript.Result
