#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" GAL_PLAYER_DECODER sw phone "Hardware decoder: OFF (software decoder)"
exit 0
