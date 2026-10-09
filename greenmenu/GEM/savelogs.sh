#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "Android Auto cluster map: save logs"
sh "$PKG/collect_logs.sh"
exit 0
