#!/bin/sh
. /fs/sda0/AAClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
echo "CarPlay map on the cluster: uninstall (the Android Auto map is left alone)"
sh "$PKG/carplay.sh" uninstall
exit 0
