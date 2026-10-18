#!/bin/sh
# As "Collect files for porting", plus the 55 MB Java interface image that a
# turn-arrows port needs. Takes about a minute.
HERE=`dirname "$0"`
[ -f /fs/sda0/ClusterMap/GEM/collect_for_porting.sh ] && HERE=/fs/sda0/ClusterMap/GEM
exec sh "$HERE/collect_for_porting.sh" --full
