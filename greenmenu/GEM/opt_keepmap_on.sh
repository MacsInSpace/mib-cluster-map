#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_PLAYER_REASSERT 1 phone "Keep the phone's map: ON. The player switches the cockpit back when the unit puts its own map there"
exit 0
