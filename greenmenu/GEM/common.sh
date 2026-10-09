# Sourced by the green menu entries. Finds the package folder on the SD card,
# makes the card writable and checks the firmware train.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
# Firmware trains with a car-tested profile in the hook, space separated.
SUPPORTED_TRAINS="MHI2_ER_VWG13_P4521"
SUPPORTED_TRAIN="$SUPPORTED_TRAINS"

PKG=
for v in /fs/sda0 /fs/sdb0 /net/mmx/fs/sda0 /net/mmx/fs/sdb0; do
    if [ -f "$v/AAClusterMap/enable_hook.sh" ]; then PKG="$v/AAClusterMap"; VOLUME="$v"; break; fi
done
if [ -z "$PKG" ]; then
    echo "AAClusterMap folder not found on the SD card."
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
train_supported()
{
    for t in $SUPPORTED_TRAINS; do
        case "$TRAIN" in
            *${t}*) SUPPORT_NOTE="tested firmware"; return 0 ;;
        esac
    done
    g=`wc -c < /mnt/app/eso/bin/apps/gal 2>/dev/null | sed 's/ //g'`
    r=`wc -c < /mnt/app/eso/lib/libautoreceiver.so 2>/dev/null | sed 's/ //g'`
    if [ "$g" = "$GAL_SIZE" ] && [ "$r" = "$RECEIVER_SIZE" ]; then
        SUPPORT_NOTE="UNTESTED firmware, but its Android Auto files match the tested ones in size"
        return 0
    fi
    SUPPORT_NOTE="different Android Auto files (gal $g, receiver $r bytes)"
    return 1
}
