#!/bin/sh
# CarPlay map on the cluster, side by side with the Android Auto cluster map.
#
#   carplay.sh status
#   carplay.sh install 790|791    run omonob's CarPlay Maps VC installer
#   carplay.sh uninstall          take it out again, leaving the AA map alone
#
# CarPlay Maps VC (github.com/omonob/MHI2-Carplay-Maps, GPL-3.0) is installed
# with its own installer, unchanged, from carplay/<MU>/<cluster>_*/ next to this
# script. 790 is the 10.25-inch Active Info Display, 791/794 the 12.3-inch one.
#
# Its own restore puts back a copy of lsd.sh taken at install time, which would
# also undo the Android Auto map's Java patches if they were changed later. So
# uninstall here does the same restore one piece at a time instead: the stock
# dio_manager back, CarPlay's two jar entries out of lsd.sh through lsd_jar.sh,
# its jar files as they were, and its folder removed.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

HERE=`cd "\`dirname "$0"\`" && pwd`
ACTION=${1:-}
CL=${2:-}
APP=/mnt/app
ROOT=$APP/carplaymaps
DIO=$APP/eso/bin/apps/dio_manager
JARS=$APP/eso/hmi/lsd/jars
LSD=$APP/eso/hmi/lsd/lsd.sh

# The firmware, as CarPlay Maps VC identifies it: by the size of the Java image.
MU=
line=`ls -ln /ifs/lsd.jxe 2>/dev/null`
set -- $line
case "$5" in
    55915411) MU=MU1102 ;;
    55840541) MU=MU1367 ;;
    55840933) MU=MU1440 ;;
esac
JXE_SIZE=$5

stop_carplay()
{
    for p in cpmap-guard carplay-cluster-supervisor altscreen-most-bridge carplay-pairing-helper; do
        slay -f $p >/dev/null 2>&1 || true
    done
}

case "$ACTION" in
    status)
        echo "CarPlay map (CarPlay Maps VC by omonob)"
        echo "  firmware: ${MU:-not supported} (lsd.jxe $JXE_SIZE bytes)"
        if [ -s "$ROOT/VERSION" ]; then
            echo "  installed: `cat $ROOT/VERSION`, profile `cat $ROOT/PROFILE 2>/dev/null`"
            if grep -q carplaymaps "$DIO" 2>/dev/null; then echo "  dio_manager: wrapped (active)"; else echo "  dio_manager: stock (NOT active)"; fi
            for p in carplay-cluster-supervisor altscreen-most-bridge carplay-pairing-helper; do
                if pidin -p $p >/dev/null 2>&1 && pidin -p $p | grep -q $p; then echo "  $p: running"; else echo "  $p: not running"; fi
            done
        else
            echo "  installed: no"
        fi
        ls -d "$HERE"/carplay/*/*_* 2>/dev/null | sed 's|.*/carplay/|  on the card: |'
        ;;
    install)
        case "$CL" in 790|791) ;; *) echo "usage: $0 install 790|791" >&2; exit 2 ;; esac
        [ -n "$MU" ] || { echo "NOT SUPPORTED: CarPlay Maps VC does not know this firmware (lsd.jxe $JXE_SIZE bytes). Nothing was changed."; exit 1; }
        if [ "$MU" = MU1440 ] && [ "$CL" != 790 ]; then echo "NOT SUPPORTED: MU1440 works with the 790 cluster only. Nothing was changed."; exit 1; fi
        DIR=
        for d in "$HERE"/carplay/${MU}*/${CL}_*; do [ -f "$d/run-install.sh" ] && DIR=$d; done
        [ -n "$DIR" ] || { echo "The CarPlay files for $MU / $CL are not on the card (carplay/${MU}/${CL}_...). Nothing was changed."; exit 1; }
        echo "Installing CarPlay Maps VC from $DIR"
        /bin/ksh "$DIR/run-install.sh"
        ;;
    uninstall)
        [ -d "$ROOT" ] || { echo "CarPlay Maps VC is not installed; nothing to do."; exit 0; }
        REAL=$ROOT/stock_first/dio_manager.real
        line=`ls -ln "$REAL" 2>/dev/null`; set -- $line
        [ "${5:-0}" -gt 500000 ] 2>/dev/null || { echo "CARPLAY_UNINSTALL_FAILED: the saved stock dio_manager is missing; nothing was changed." >&2; exit 1; }
        mount -uw $APP || { echo "CARPLAY_UNINSTALL_FAILED: cannot make $APP writable." >&2; exit 1; }
        stop_carplay
        if grep -q carplaymaps "$DIO" 2>/dev/null; then
            cp "$REAL" "$DIO.restore" && chmod 755 "$DIO.restore" && mv "$DIO.restore" "$DIO" || {
                rm -f "$DIO.restore"; mount -ur $APP 2>/dev/null
                echo "CARPLAY_UNINSTALL_FAILED: could not put the stock dio_manager back; nothing else was changed." >&2; exit 1; }
            echo "Stock dio_manager restored."
        fi
        # Each jar: back to the copy that was there before, or gone if there
        # was none (then its lsd.sh entry goes too).
        for J in CarPlayClusterControls CarPlayNavigationPatch; do
            if [ -s "$ROOT/rollback/$J.jar" ]; then
                cp "$ROOT/rollback/$J.jar" "$JARS/$J.jar"
                echo "$J.jar: previous copy restored."
            else
                sh "$HERE/lsd_jar.sh" remove $J.jar || { mount -ur $APP 2>/dev/null; echo "CARPLAY_UNINSTALL_FAILED at the $J.jar entry; lsd.sh is unchanged." >&2; exit 1; }
                mount -uw $APP
                rm -f "$JARS/$J.jar"
            fi
        done
        rm -rf "$ROOT"
        sync
        mount -ur $APP 2>/dev/null
        echo "CARPLAY_UNINSTALL_OK"
        echo "Hold the power button for 10 seconds to reboot the unit."
        ;;
    *) echo "usage: $0 status|install 790|791|uninstall" >&2; exit 2 ;;
esac
