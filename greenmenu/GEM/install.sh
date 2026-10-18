#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The one install entry for every unit. It picks the best this firmware can do:
#   1. the Android Auto map on the cluster, where the hook has a profile;
#   2. otherwise the turn-by-turn arrows, where that jar is known to work;
#   3. otherwise nothing: NOT SUPPORTED (the update then collects porting files).
echo "Android Auto on the digital cluster: install"
echo "Head unit: $FAMILY"
echo "Firmware train: $TRAIN"
if train_supported; then
    echo "Compatibility: $SUPPORT_NOTE"
    echo "Installing: the Android Auto map on the cluster"
    sh "$PKG/enable_hook.sh"
    RC=$?
    echo
    if [ $RC -eq 0 ]; then
        echo "AACLUSTER_INSTALL_OK"
    else
        echo "AACLUSTER_INSTALL_FAILED (code $RC). Read the messages above."
    fi
    # The CarPlay map too, when its files are on the card and the cockpit
    # type is known. It never touches the Android Auto map.
    if [ $RC -eq 0 ] && ls -d "$PKG"/carplay/*/79*_* >/dev/null 2>&1; then
        echo
        if [ -d /mnt/app/carplaymaps ]; then
            echo "CarPlay map: already installed, left as it is."
        elif sh "$PKG/carplay.sh" install auto; then
            echo "CARPLAY_INSTALL_OK"
        else
            echo "CarPlay map: not installed (see above). The Android Auto map is unaffected."
        fi
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
        echo "AACLUSTER_TURN_BY_TURN_OK"
        echo "Hold the power button for 10 seconds to reboot the unit."
    else
        echo "AACLUSTER_INSTALL_FAILED (code $RC). Read the messages above."
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
