# Shared by enable_hook.sh and disable_hook.sh: where the preload target
# lives on the internal /mnt/app partition, and the mount-guard cleanup
# for it.
#
# Under /eso/lib specifically, not /navigation: this firmware's own
# smartphone_integrator.json already has a "mirrorlink" child using
# LD_PRELOAD=/eso/lib/libsystemtime_hack.so, direct proof (not just
# analogy) that this exact framework relies on LD_PRELOAD from this exact
# path working reliably for a supervised child. /navigation was considered
# and rejected: it is also on /mnt/app and would likely work the same way,
# but it holds map/POI data content that a future navigation update could
# resync or clean, silently deleting an unrelated subdirectory placed
# inside it. /eso/lib is vendor framework code, not managed content, and
# is not going to be swept by anything that isn't a full firmware update.
APP_MOUNT=/mnt/app
PRELOAD_WRITE_DIR="$APP_MOUNT/eso/lib/gal_dualscreen"
PRELOAD_SO_ALIAS=/eso/lib/gal_dualscreen/libgal_hook.so
PRELOAD_SO_REAL="$PRELOAD_WRITE_DIR/libgal_hook.so"
APP_WRITABLE=0

# Callers should call this from their own finish()/trap handler, after
# handling whatever else that script's finish() is responsible for (e.g.
# SYSTEM_MOUNT cleanup, which is script-specific and not handled here).
app_mount_finish()
{
    if [ "$APP_WRITABLE" -eq 1 ]; then
        # Do not swallow a failed remount. This runs from a trap, so the
        # exit status goes nowhere -- but leaving the internal partition
        # writable is not a cosmetic problem on a device that loses power
        # by having its ignition switched off, and the operator is the
        # only one who can act on it. The flag is cleared only on success,
        # so a caller that runs this twice will try again.
        if mount -ur "$APP_MOUNT" 2>/dev/null; then
            APP_WRITABLE=0
        else
            echo "WARNING: could not remount $APP_MOUNT read-only." >&2
            echo "         It is still writable. Run:  mount -ur $APP_MOUNT" >&2
            echo "         before switching the car off." >&2
        fi
    fi
}

# The CarPlay map's firewall rule. The iPhone sends the cluster video to
# TCP 6031 (harman-f's stream 111 receiver), but the unit's packet filter
# drops every port on carplay0 (the iPhone's USB link) that is not in its
# CarPlay list, and 6031 is not (car-verified on a Golf R: the phone set up
# the stream and never connected). One pass rule for that port on carplay0
# only is added after the stock CarPlay line, in each /mnt/system/etc/pf*.conf
# (the unit picks one by connection type), as the MIB2 Toolbox does for SSH.
# Marked, so removal takes out only our line; read at the next boot.
# Both need $SYSTEM_MOUNT writable.
CARPLAY_PF_MARK="# clustermap carplay map"
CARPLAY_PF_RULE="pass in quick on carplay0 proto tcp from any to any port 6031 allow-opts $CARPLAY_PF_MARK"

carplay_pf_close()
{
    for PF in /mnt/system/etc/pf*.conf; do
        [ -f "$PF" ] && grep -q "$CARPLAY_PF_MARK" "$PF" || continue
        cp -p "$PF" "$PF.clustermap-new" &&
            grep -v "$CARPLAY_PF_MARK" "$PF" > "$PF.clustermap-new" &&
            mv "$PF.clustermap-new" "$PF" && echo "Firewall: CarPlay map port closed in $PF"
    done
}

carplay_pf_open()
{
    carplay_pf_close >/dev/null
    for PF in /mnt/system/etc/pf*.conf; do
        [ -f "$PF" ] && grep -q '^pass in quick on carplay0 proto tcp ' "$PF" || continue
        [ -f "$PF.clustermap.original" ] || cp -p "$PF" "$PF.clustermap.original"
        # Started as a copy so the file keeps its owner and mode.
        cp -p "$PF" "$PF.clustermap-new" && awk -v rule="$CARPLAY_PF_RULE" '
            { print }
            !done && /^pass in quick on carplay0 proto tcp / { print rule; done=1 }
        ' "$PF" > "$PF.clustermap-new" && grep -q "$CARPLAY_PF_MARK" "$PF.clustermap-new" &&
            mv "$PF.clustermap-new" "$PF" && echo "Firewall: CarPlay map port 6031 opened on carplay0 in $PF" ||
            { rm -f "$PF.clustermap-new"; echo "Firewall: could not edit $PF; the CarPlay map may get no video"; }
    done
}
