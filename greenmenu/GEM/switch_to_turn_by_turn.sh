#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
echo "Switch to turn-by-turn arrows (removes the cluster map)"
echo "Firmware train: $TRAIN"
if ! tbt_supported; then
    echo "NOT SUPPORTED: the turn-by-turn jar is only known to work on"
    echo "$TBT_TRAINS. Nothing was changed."
    exit 0
fi
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null; then
    echo "Removing the cluster map first..."
    sh "$PKG/disable_hook.sh" --keep-jar-removed || { echo "CLUSTERMAP_SWITCH_FAILED: uninstall failed, nothing else was changed."; exit 0; }
fi
sh "$PKG/turn_by_turn.sh" install
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_TURN_BY_TURN_OK"
    echo "Hold the power button for 10 seconds to reboot the unit."
else
    echo "CLUSTERMAP_SWITCH_FAILED (code $RC). Read the messages above."
fi
exit 0
