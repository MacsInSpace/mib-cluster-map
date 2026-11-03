#!/bin/sh
# Green menu entry: sharper map ON (Android Auto draws on the whole frame).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/full_frame.sh" on
exit 0
