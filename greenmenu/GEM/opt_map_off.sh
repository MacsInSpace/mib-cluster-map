#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_DUALSCREEN_ENABLE 0 reboot "Cluster map: OFF. Android Auto runs as before the install; nothing is removed"
exit 0
