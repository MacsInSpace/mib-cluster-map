#!/bin/sh
# Insets per cockpit view (#183, kashavsehra): tells the hook which view the
# cockpit shows, and the phone gets that view's insets at once. Only does
# anything with GAL_SECONDARY_LARGE_INSETS or GAL_SECONDARY_SPORT_INSETS set.
. "`dirname "$0"`/common.sh"
CONF=/mnt/app/eso/lib/gal_dualscreen/gal_dualscreen.conf
if grep -q '^GAL_SECONDARY_LARGE_INSETS=[0-9]' "$CONF" 2>/dev/null ||
   grep -q '^GAL_SECONDARY_SPORT_INSETS=[0-9]' "$CONF" 2>/dev/null; then
    echo sport > /tmp/gal_view
    echo "Map insets: sport view sent (the phone redraws in a moment)."
else
    echo "Map insets per view are off: set GAL_SECONDARY_LARGE_INSETS or"
    echo "GAL_SECONDARY_SPORT_INSETS in gal_dualscreen.conf and install again."
fi
exit 0
