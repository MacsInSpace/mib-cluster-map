#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_DUALSCREEN_ENABLE 1 reboot "Cluster map: ON"
exit 0
