# Sourced by the green menu entries. Finds the package folder on the SD card,
# makes the card writable and checks the firmware train.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
# Firmware trains with a car-tested profile in the hook, space separated.
# Matched as substrings, so re-releases such as MHI2_ER_VWG13_P4521_2 count;
# the hook still checks the real addresses when it loads. K4525 runs the
# P4521 profile unchanged (two owners, issue #5).
SUPPORTED_TRAINS="MHI2_ER_VWG13_P4521 MHI2_ER_VWG13_K4525 MHI2_ER_SEG11_P4708 MHI2_ER_SEG11_P4709"
SUPPORTED_TRAIN="$SUPPORTED_TRAINS"

PKG=
for v in /fs/sda0 /fs/sdb0 /net/mmx/fs/sda0 /net/mmx/fs/sdb0; do
    if [ -f "$v/ClusterMap/enable_hook.sh" ]; then PKG="$v/ClusterMap"; VOLUME="$v"; break; fi
done
if [ -z "$PKG" ]; then
    echo "ClusterMap folder not found on the SD card."
    exit 0
fi
mount -uw "$VOLUME" 2>/dev/null

TRAIN=unknown
for f in /net/rcc/dev/shmem/version.txt /dev/shmem/version.txt; do
    if [ -r "$f" ]; then
        TRAIN=`grep "Current train" "$f" | sed 's/Current train = //' | sed -e 's|["'"'"']||g' | sed 's/\r//'`
        break
    fi
done

# The tested train, or an untested train whose two Android Auto binaries have
# exactly the sizes of the tested ones. The hook checks the real addresses
# itself when it loads and leaves Android Auto stock on any mismatch, so this
# gate only exists to stop an install that cannot work.
GAL_SIZE=1269211
RECEIVER_SIZE=1067402
SUPPORT_NOTE=
# The Android Auto receiver library, which the hook attaches to and every
# profile is measured against. MIB2.5 High units call it libautoreceiver.so
# and keep it in /mnt/app/eso/lib, with a second copy at /eso/lib. The older
# VWG11 generation links libautoreceiver_qnx.so.1 beside libaoa-lite instead
# (issue #28: Vladimir's K3342 gal names it in its DT_NEEDED), so a unit that
# has no libautoreceiver.so has not necessarily no receiver. Look for every
# known name before concluding that.
RECEIVER_NAMES="libautoreceiver.so libautoreceiver_qnx.so.1"
RECEIVER_DIRS="/mnt/app/eso/lib /eso/lib /mnt/app/armle/lib /mnt/app/usr/lib /mnt/app/root/lib-target"
receiver_path()
{
    for d in $RECEIVER_DIRS; do
        for n in $RECEIVER_NAMES; do
            if [ -r "$d/$n" ]; then echo "$d/$n"; return 0; fi
        done
    done
    return 1
}
train_supported()
{
    for t in $SUPPORTED_TRAINS; do
        case "$TRAIN" in
            *${t}*) SUPPORT_NOTE="tested firmware"; return 0 ;;
        esac
    done
    g=`wc -c < /mnt/app/eso/bin/apps/gal 2>/dev/null | sed 's/ //g'`
    RECEIVER_FOUND=`receiver_path`
    r=`wc -c < "$RECEIVER_FOUND" 2>/dev/null | sed 's/ //g'`
    if [ "$g" = "$GAL_SIZE" ] && [ "$r" = "$RECEIVER_SIZE" ]; then
        SUPPORT_NOTE="UNTESTED firmware, but its Android Auto files match the tested ones in size"
        return 0
    fi
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

# Firmware where adi961's turn-arrows jar (VCAndroidAuto.jar) is known to
# work: the jar author's two VW trains, and the two SEAT trains its owners
# report working (issue #3). The jar replaces Java classes of the unit's
# interface; on a firmware it does not fit, the centre screen may not start,
# so it is never installed on any other train.
TBT_TRAINS="MHI2_ER_VWG13_P4521 MHI2_ER_VWG13_K4525 MHI2_ER_SEG11_P4708 MHI2_ER_SEG11_P4709"
tbt_supported()
{
    for t in $TBT_TRAINS; do
        case "$TRAIN" in *${t}*) return 0 ;; esac
    done
    return 1
}

# The head unit family, from the train name, for messages only.
case "$TRAIN" in
    MHI2Q_*) FAMILY="Audi MIB2 High, Qualcomm (MHI2Q)" ;;
    MHI2_*)  FAMILY="Harman MIB2 / MIB2.5 High (MHI2)" ;;
    MST2_*)  FAMILY="MIB2 Standard (Technisat/Preh, MST2)" ;;
    *)       FAMILY="unknown" ;;
esac
