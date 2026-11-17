#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_PLAYER_REASSERT 0 phone "Keep the phone's map: OFF"
exit 0
