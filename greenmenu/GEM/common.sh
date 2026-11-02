# Sourced by the green menu entries. Finds the package folder, on whichever
# card or USB stick these scripts run from, makes it writable and checks the
# firmware train.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

# The scripts' own folder first: the update can run from a USB stick (#24)
# or the second SD slot, and a card that is not /fs/sda0 must not be missed.
PKG=
HERE=`cd "\`dirname "$0"\`" 2>/dev/null && pwd`
if [ -f "$HERE/../enable_hook.sh" ]; then
    PKG=`cd "$HERE/.." && pwd`
    VOLUME=`dirname "$PKG"`
else
    for v in /fs/sda0 /fs/sdb0 /fs/usb0_0 /fs/usb1_0 /net/mmx/fs/sda0 /net/mmx/fs/sdb0; do
        if [ -f "$v/ClusterMap/enable_hook.sh" ]; then PKG="$v/ClusterMap"; VOLUME="$v"; break; fi
    done
fi
if [ -z "$PKG" ]; then
    echo "ClusterMap folder not found on the SD card or USB stick."
    exit 0
fi
mount -uw "$VOLUME" 2>/dev/null
# A failed "." ends the shell, and with it the whole install, so check first.
if [ ! -r "$PKG/scripts/lib_unit.sh" ] || [ ! -r "$PKG/profiles.conf" ]; then
    echo "This ClusterMap folder is incomplete: unpack the release zip again."
    exit 0
fi
. "$PKG/scripts/lib_unit.sh"

TRAIN=unknown
for f in /net/rcc/dev/shmem/version.txt /dev/shmem/version.txt; do
    if [ -r "$f" ]; then
        TRAIN=`grep "Current train" "$f" | sed 's/Current train = //' | sed -e 's|["'"'"']||g' | sed 's/\r//'`
        break
    fi
done

# Whether the map can be installed. profiles.conf holds the car-tested trains;
# any other train counts when its gal is a build we have a profile for, which
# profile_check reads from the file. The hook checks the same addresses itself
# when it loads and leaves Android Auto stock on any mismatch, so this gate only
# exists to stop an install that cannot work.
SUPPORT_NOTE=
# The two phone libraries this project attaches to, and where units keep them.
#
# Android Auto: MIB2.5 High units call it libautoreceiver.so and keep it in
# /mnt/app/eso/lib, with a second copy at /eso/lib. The older VWG11
# generation links libautoreceiver_qnx.so.1 beside libaoa-lite instead
# (issue #28: Vladimir's K3342 gal names it in its DT_NEEDED), so a unit with
# no libautoreceiver.so has not necessarily no receiver.
#
# CarPlay: libairplay.so, which the CarPlay hook attaches to by exported
# symbol name. Collected for the same reason as the receiver -- it is what a
# port has to be checked against, and asking for it afterwards costs a round
# trip (issue #10, US P3662, whose build differs from the tested one).
LIB_DIRS="/mnt/app/eso/lib /eso/lib /mnt/app/armle/lib /mnt/app/usr/lib /mnt/app/root/lib-target"
RECEIVER_NAMES="libautoreceiver.so libautoreceiver_qnx.so.1"
AIRPLAY_NAMES="libairplay.so"
# First readable file among the names given, in the library folders.
lib_path()
{
    for d in $LIB_DIRS; do
        for n in "$@"; do
            if [ -r "$d/$n" ]; then echo "$d/$n"; return 0; fi
        done
    done
    return 1
}
receiver_path() { lib_path $RECEIVER_NAMES; }
airplay_path()  { lib_path $AIRPLAY_NAMES; }
train_supported()
{
    # VWG11 before K3342: not supported, update first (#39; install.sh).
    case "$TRAIN" in
        *_VWG11_S*) SUPPORT_NOTE="not supported: update to MHI2_ER_VWG11_K3342_1_AIO_MU1427 first (#39)"; return 1 ;;
    esac
    # PROBE_OUT is also what tells us about a unit that is not supported.
    unit_gal_check "$PKG" || PROBE_OUT=
    if train_has "$PKG/profiles.conf" "$TRAIN" map; then
        SUPPORT_NOTE="tested firmware"
        return 0
    fi
    if [ -n "$PROBE_MATCH" ]; then
        SUPPORT_NOTE="this train is not listed, but its Android Auto program is the $PROBE_MATCH build"
        return 0
    fi
    g=`wc -c < /mnt/app/eso/bin/apps/gal 2>/dev/null | sed 's/ //g'`
    RECEIVER_FOUND=`receiver_path`
    r=`wc -c < "$RECEIVER_FOUND" 2>/dev/null | sed 's/ //g'`
    # A trial profile for this train in the settings file (as find_profile.py
    # prints it): installed for testing. The hook checks the real addresses
    # when it loads and does nothing if they differ.
    p=`sed -n 's/^GAL_PROFILE_TRIAL=\([^:]*\):.*/\1/p' "$PKG/gal_dualscreen.conf" 2>/dev/null | head -1`
    if [ -n "$p" ]; then
        case "$TRAIN" in
            *${p}*) SUPPORT_NOTE="UNTESTED firmware, with the trial profile $p from gal_dualscreen.conf"; return 0 ;;
        esac
    fi
    if [ -z "$RECEIVER_FOUND" ]; then
        SUPPORT_NOTE="no Android Auto receiver library found (gal $g bytes)"
    else
        SUPPORT_NOTE="different Android Auto files (gal $g, `echo "$RECEIVER_FOUND" | sed 's|.*/||'` $r bytes)"
    fi
    return 1
}

# Firmware where adi961's turn-arrows jar (VCAndroidAuto.jar) is known to work
# ("arrows" in profiles.conf). The jar replaces Java classes of the unit's
# interface; on a firmware it does not fit, the centre screen may not start, so
# it is never installed on any other train.
tbt_supported() { train_has "$PKG/profiles.conf" "$TRAIN" arrows; }

# What a run that installs nothing has still left behind, said plainly: #10
# found B201A00 and a sporadic U10CF00 logged at the minute of the SD update,
# before anything of this project ran.
nothing_installed()
{
    echo "Nothing was installed. The green menu screen was added, which Uninstall"
    echo "removes. A software update from SD can also log fault B201A00 (Check"
    echo "Software Version Management) in the head unit; see docs/Install.md."
}

# The head unit family, from the train name, for messages only.
case "$TRAIN" in
    MHI2Q_*) FAMILY="Audi MIB2 High, Qualcomm (MHI2Q)" ;;
    MHI2_*)  FAMILY="Harman MIB2 / MIB2.5 High (MHI2)" ;;
    MST2_*)  FAMILY="MIB2 Standard (Technisat/Preh, MST2)" ;;
    *)       FAMILY="unknown" ;;
esac
