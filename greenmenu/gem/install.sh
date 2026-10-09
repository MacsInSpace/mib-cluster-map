#!/bin/sh
. /fs/sda0/AAClusterMap/gem/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Android Auto cluster map: install"
echo "Firmware train: $TRAIN"
if ! train_supported; then
    echo "NOT SUPPORTED: this package is for $SUPPORTED_TRAIN."
    echo "Reason: $SUPPORT_NOTE"
    echo "Nothing was changed."
    exit 0
fi
echo "Compatibility: $SUPPORT_NOTE"
sh "$PKG/enable_hook.sh"
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "AACLUSTER_INSTALL_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "AACLUSTER_INSTALL_FAILED (code $RC). Read the messages above."
fi
exit 0
