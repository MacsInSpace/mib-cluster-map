#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_SECONDARY_UI_THEME 0 reboot "Map colours: follow the headlights"
exit 0
