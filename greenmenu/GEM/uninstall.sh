#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Android Auto on the digital cluster: uninstall and restore the original state"
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
echo
if [ $RC -eq 0 ]; then
    echo "AACLUSTER_UNINSTALL_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "AACLUSTER_UNINSTALL_FAILED (code $RC). Read the messages above."
fi
exit 0
