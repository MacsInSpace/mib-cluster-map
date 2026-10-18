#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "CarPlay map on the cluster: install for the 790 (10.25-inch) cockpit"
echo "Firmware train: $TRAIN"
sh "$PKG/carplay.sh" install 790
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "CARPLAY_INSTALL_FAILED (code $RC). Read the messages above."
fi
exit 0
