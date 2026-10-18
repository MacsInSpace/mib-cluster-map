#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The one install entry for every unit. It picks the best this firmware can do:
#   1. the Android Auto map on the cluster, where the hook has a profile;
#   2. otherwise the turn-by-turn arrows, where that jar is known to work;
#   3. otherwise nothing: NOT SUPPORTED (the update then collects porting files).
echo "Phone map on the digital cluster: install"
# The menu screen of v1.0.0 was called aa-cluster-map.esd and runs scripts from
# an AAClusterMap folder that newer cards do not have. Once this version's
# screen is on the unit, the old one only leads nowhere, so it goes.
ENGDEFS=/mnt/app/eso/hmi/engdefs
if [ -f $ENGDEFS/aa-cluster-map.esd ] && [ -f $ENGDEFS/cluster-map.esd ]; then
    mount -uw /mnt/app 2>/dev/null && rm -f $ENGDEFS/aa-cluster-map.esd && echo "Removed the old AAClusterMap menu screen."; mount -ur /mnt/app 2>/dev/null
fi
echo "Head unit: $FAMILY"
echo "Firmware train: $TRAIN"
if train_supported; then
    echo "Compatibility: $SUPPORT_NOTE"
    echo "Installing: the Android Auto map on the cluster"
    sh "$PKG/enable_hook.sh"
    RC=$?
    echo
    if [ $RC -eq 0 ]; then
        echo "CLUSTERMAP_INSTALL_OK"
    else
        echo "CLUSTERMAP_INSTALL_FAILED (code $RC). Read the messages above."
    fi
    [ $RC -eq 0 ] && echo "Hold the power button for 10 seconds to reboot the unit."
    exit 0
fi
echo "The cluster map is not available on this firmware yet ($SUPPORT_NOTE)."
if tbt_supported; then
    echo "Installing instead: turn-by-turn arrows on the cluster (adi961's VCAndroidAuto.jar)"
    sh "$PKG/turn_by_turn.sh" install
    RC=$?
    echo
    if [ $RC -eq 0 ]; then
        echo "CLUSTERMAP_TURN_BY_TURN_OK"
        echo "Hold the power button for 10 seconds to reboot the unit."
    else
        echo "CLUSTERMAP_INSTALL_FAILED (code $RC). Read the messages above."
    fi
    exit 0
fi
echo "NOT SUPPORTED: neither the cluster map nor the turn-by-turn arrows are known"
echo "to work on $TRAIN. Nothing was changed."
case "$TRAIN" in
    MHI2Q_*) echo "For Audi MHI2Q units see github.com/kamgurgul/mib2q-carplay (CarPlay and Android Auto)." ;;
    MST2_*)  echo "MIB2 Standard units are a different design; nothing in this package applies." ;;
esac
exit 0
