#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
echo "Switch to turn-by-turn arrows (removes the cluster map)"
echo "Firmware train: $TRAIN"
# The jar's author lists these two trains as tested.
case "$TRAIN" in
    *MHI2_ER_VWG13_P4521*|*MHI2_ER_VWG13_K4525*) ;;
    *) echo "NOT SUPPORTED: the turn-by-turn jar is only tested on"
       echo "MHI2_ER_VWG13_P4521 and MHI2_ER_VWG13_K4525. Nothing was changed."
       exit 0 ;;
esac
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null; then
    echo "Removing the cluster map first..."
    sh "$PKG/disable_hook.sh" --keep-jar-removed || { echo "AACLUSTER_SWITCH_FAILED: uninstall failed, nothing else was changed."; exit 0; }
fi
sh "$PKG/turn_by_turn.sh" install
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "AACLUSTER_TURN_BY_TURN_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "AACLUSTER_SWITCH_FAILED (code $RC). Read the messages above."
fi
exit 0
