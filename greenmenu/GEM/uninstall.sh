#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Android Auto cluster map: uninstall and restore the original state"
sh "$PKG/disable_hook.sh"
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "AACLUSTER_UNINSTALL_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "AACLUSTER_UNINSTALL_FAILED (code $RC). Read the messages above."
fi
exit 0
