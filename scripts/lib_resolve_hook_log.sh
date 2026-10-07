# Sourced by hook_status.sh. Upstream never published this helper, so this is a
# local reconstruction from how hook_status.sh uses it: print the hook log that
# exists, preferring the SD-card path, then the RAM fallback the hook uses when
# the card is read-only or absent. Always prints a path, even if none exists.
#
# Expects HOOK_LOG_SD and HOOK_LOG_TMP to be set by the caller.
resolve_hook_log()
{
    for _candidate in "$HOOK_LOG_SD" /fs/sda0/logs/gal_dualscreen.log \
                      /fs/sdb0/logs/gal_dualscreen.log "$HOOK_LOG_TMP"; do
        if [ -r "$_candidate" ]; then
            echo "$_candidate"
            return 0
        fi
    done
    echo "$HOOK_LOG_SD"
    return 0
}
