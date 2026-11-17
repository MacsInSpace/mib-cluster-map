#!/bin/sh
# Green menu entry: can this unit's own video decoder be used for the map?
# Decodes a one-second test clip into memory and compares every picture with
# the reference. Changes nothing; GAL_PLAYER_DECODER=hw is switched on from
# ClusterMapOptions.
. "`dirname "$0"`/common.sh"
echo "Phone map on the digital cluster: hardware decoder check"
echo "Firmware train: $TRAIN"
hw_libs
if hw_check; then
    echo "This unit can decode the map with its own decoder, at about a third of"
    echo "the processor time. Switch it on: ClusterMapOptions > Hardware decoder ON."
else
    echo "Leave the hardware decoder off on this unit. Please report this screen"
    echo "(the details are in ClusterMap/logs/hw_check.txt on the card)."
fi
exit 0
