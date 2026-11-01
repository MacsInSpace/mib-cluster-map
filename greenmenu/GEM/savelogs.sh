#!/bin/sh
. "`dirname "$0"`/common.sh"
echo "Phone map on the digital cluster: save logs"
sh "$PKG/collect_logs.sh"
exit 0
