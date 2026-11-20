#!/bin/sh
. "`dirname "$0"`/common.sh"
echo "Phone map on the digital cluster: save logs"
echo "Saving, please wait for \"Done\" (do not press again)."
sh "$PKG/collect_logs.sh"
exit 0
