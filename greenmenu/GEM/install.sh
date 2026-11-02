#!/bin/sh
. "`dirname "$0"`/common.sh"
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
# Before anything changes: a unit without a command the scripts need stops
# here and says which, instead of failing half way through.
unit_tools
[ -z "$UNIT_ABSENT" ] || echo "Not on this unit:$UNIT_ABSENT"
if [ -n "$UNIT_MISSING" ]; then
    echo
    echo "NOT INSTALLED: this unit has no$UNIT_MISSING, which the installer needs."
    nothing_installed
    echo "Please post this message in a new issue."
    echo "CLUSTERMAP_TOOLS_MISSING$UNIT_MISSING"
    exit 0
fi
# VWG11 before K3342 (S2125): NavActiveIgnore stopped Android Auto there and
# the map went at every route (#39). Owners who updated to K3342 have it
# working, so say that instead of installing or collecting, even with a
# trial line.
case "$TRAIN" in
    *_VWG11_S*)
        echo
        echo "=================================================================="
        echo "NOT SUPPORTED: $TRAIN (VW Discover Pro 8 in, original firmware)."
        nothing_installed
        echo
        echo "On this firmware the map is lost when a route starts, and the fix"
        echo "for that stopped Android Auto (#39). Update the unit to"
        echo "  MHI2_ER_VWG11_K3342_1_AIO_MU1427"
        echo "(through a VW dealer or a firmware package you trust), check the"
        echo "train and MU in the green menu, then run this update again with"
        echo "CLUSTERMAP_ADD_NAVIGNORE=1. Owners' Passat B8s work that way (#39)."
        echo "Updating firmware is at your own risk."
        echo "=================================================================="
        echo "CLUSTERMAP_UPDATE_FIRMWARE_FIRST"
        exit 0 ;;
esac
if train_supported; then
    [ -z "$PROBE_OUT" ] || echo "$PROBE_OUT"
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
echo "to work on $TRAIN."
nothing_installed
case "$TRAIN" in
    MHI2Q_*) echo "For Audi MHI2Q units see github.com/kamgurgul/mib2q-carplay (CarPlay and Android Auto)." ;;
    MST2_*)  echo "MIB2 Standard units are a different design; nothing in this package applies." ;;
esac
exit 0
