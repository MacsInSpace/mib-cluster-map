#!/bin/sh
# Run on the head unit after a test (green menu "Save logs to SD", or over SSH).
# Copies the hook and player logs plus system state to the SD card (run_logs/).
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
# The folder this script sits in is the package folder; logs go beside it.
HERE=`cd "\`dirname "$0"\`" && pwd`
case "$HERE" in
    /fs/sdb0*|/net/mmx/fs/sdb0*) SD=/fs/sdb0 ;;
    *) SD=/fs/sda0 ;;
esac
mount -uw $SD 2>/dev/null
OUT=$HERE/run_logs
mkdir -p $OUT
cp /tmp/gal_dualscreen.log /tmp/stream-player.log /tmp/gal_kombi_ready $OUT/ 2>/dev/null
sloginfo > $OUT/sloginfo.txt 2>&1
pidin ar > $OUT/pidin_ar.txt 2>&1
ls -l /mnt/ota /mnt/ota/* /var/dumps /tmp > $OUT/dumps_listing.txt 2>&1
ls -l /lib/libEGL* /lib/libGLESv2* /usr/lib/libEGL* > $OUT/gl_libs.txt 2>&1
grep -n "gal" /mnt/system/etc/eso/production/smartphone_integrator.json > $OUT/gal_config_lines.txt 2>&1
sh $HERE/scripts/hook_status.sh > $OUT/status.txt 2>&1
sync 2>/dev/null
ls -l $OUT
echo "Done. Wait a few seconds, then take the SD card to the laptop."
