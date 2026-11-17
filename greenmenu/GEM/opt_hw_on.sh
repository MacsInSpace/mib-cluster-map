#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_PLAYER_DECODER hw phone "Hardware decoder: ON. If this unit cannot use it, the player falls back to software by itself"
exit 0
