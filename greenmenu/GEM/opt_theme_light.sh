#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_SECONDARY_UI_THEME 1 reboot "Map colours: always light (Google Maps; Waze stays dark)"
exit 0
