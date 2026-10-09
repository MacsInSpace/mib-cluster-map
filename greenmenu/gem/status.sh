#!/bin/sh
. /fs/sda0/AAClusterMap/gem/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
LSD=/mnt/app/eso/hmi/lsd/lsd.sh
echo "Android Auto cluster map: status"
echo "Package folder: $PKG"
echo "Firmware train: $TRAIN"
if train_supported; then echo "  supported: yes ($SUPPORT_NOTE)"; else echo "  supported: NO, needs $SUPPORTED_TRAIN ($SUPPORT_NOTE)"; fi
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null; then echo "Hook: installed"; else echo "Hook: not installed"; fi
if [ -f /mnt/app/eso/lib/gal_dualscreen/libgal_hook.so ]; then echo "  library: present"; else echo "  library: missing"; fi
if [ -f /mnt/app/navigation/stream-player ]; then echo "  player: present"; else echo "  player: missing"; fi
if grep -q 'NavActiveIgnore.jar' "$LSD" 2>/dev/null; then echo "NavActiveIgnore: loaded (required)"; else echo "NavActiveIgnore: NOT loaded (required: Customization > Navigation)"; fi
if grep -q 'VCAndroidAuto.jar' "$LSD" 2>/dev/null; then echo "Turn-by-turn arrows (VCAndroidAuto.jar): loaded. Installing the map turns this off."; else echo "Turn-by-turn arrows (VCAndroidAuto.jar): not loaded"; fi
if [ -r /tmp/gal_dualscreen.log ]; then
    echo "Last hook events:"
    grep -E "event=(init |firmware.verify|secondary.register|focus.state|player.spawn|focus.loss)" /tmp/gal_dualscreen.log | tail -6 | sed 's/^gal_dualscreen //' | cut -c1-110
else
    echo "No hook log yet (connect a phone after rebooting)."
fi
exit 0
