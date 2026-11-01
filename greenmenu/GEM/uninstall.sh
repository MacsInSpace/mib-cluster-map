#!/bin/sh
. "`dirname "$0"`/common.sh"
echo "Phone map on the digital cluster: uninstall and restore the original state"
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
RC=0
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null || [ -d /mnt/app/eso/lib/gal_dualscreen ]; then
    sh "$PKG/disable_hook.sh"
    RC=$?
else
    echo "The cluster map is not installed."
fi
# The turn-by-turn arrows, when this package installed them instead of the map.
if [ -f /mnt/app/eso/hmi/lsd/.aacluster_tbt_added ]; then
    sh "$PKG/turn_by_turn.sh" uninstall || RC=1
fi
# The menu screen the update copied. Its files stay on the card, and a
# COLLECT.txt update brings it back for Save logs.
ENGDEFS=/mnt/app/eso/hmi/engdefs
if [ $RC -eq 0 ] && [ -f $ENGDEFS/cluster-map.esd ]; then
    if mount -uw /mnt/app 2>/dev/null; then
        rm -f $ENGDEFS/cluster-map.esd && echo "Removed the menu screen."
        mount -ur /mnt/app 2>/dev/null
    else
        echo "Could not remove the menu screen (harmless): $ENGDEFS/cluster-map.esd"
    fi
fi
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_UNINSTALL_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "CLUSTERMAP_UNINSTALL_FAILED (code $RC). Read the messages above."
fi
exit 0
