#!/bin/sh
# Green menu switch (scripts/menu_switch.sh). The check runs first: where it
# does not pass, the player still tries the draw-to-display method (Audi) and
# falls back to software by itself, so this warns and does not refuse.
. "`dirname "$0"`/common.sh"
if hw_check; then :; else
    echo "The in-memory decoder check did not pass on this unit. The switch is"
    echo "set anyway: the player falls back to software if it cannot use hardware."
fi
sh "$PKG/scripts/menu_switch.sh" GAL_PLAYER_DECODER hw phone "Hardware decoder: ON"
exit 0
