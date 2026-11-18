#!/bin/sh
# Make a Docker image available without rebuilding it.
#
#   tools/docker_image.sh <name:tag> [Dockerfile folder]
#
# Docker Desktop keeps images per Mac account (each account has its own VM
# disk), so a second account would otherwise rebuild the simulator and the
# QNX toolchain image from scratch. Images are kept as <name>_<tag>.tar.gz in
# $MIB_IMAGE_CACHE (default ../docker-images next to the repo, like
# ../unit_sim_units): an image present here is saved there once, and an
# account without it loads it from there. Only without either is it built
# (when a Dockerfile folder is given). Change an image's tag whenever its
# Dockerfile changes, so a stale copy is never loaded.
set -eu
IMG=$1; DIR=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE=${MIB_IMAGE_CACHE:-$ROOT/../docker-images}
TAR=$CACHE/$(echo "$IMG" | tr '/:' '__').tar.gz
have() {
    docker image inspect "$IMG" >/dev/null 2>&1 ||
        docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qx "$IMG"
}
save() {
    mkdir -p "$CACHE" 2>/dev/null || return 0
    [ -f "$TAR" ] && return 0
    echo "docker_image: saving $IMG to $TAR (once)" >&2
    docker save "$IMG" | gzip -1 > "$TAR.part.$$" && mv "$TAR.part.$$" "$TAR" || rm -f "$TAR.part.$$"
    chmod a+rw "$TAR" 2>/dev/null || :
}
if have; then save; exit 0; fi
if [ -f "$TAR" ]; then
    echo "docker_image: loading $IMG from $TAR" >&2
    gunzip -c "$TAR" | docker load >/dev/null && have && exit 0
    echo "docker_image: $TAR did not load" >&2
fi
[ -n "$DIR" ] || { echo "docker_image: $IMG not found and not in $CACHE" >&2; exit 1; }
echo "docker_image: building $IMG" >&2
docker build -q --platform linux/amd64 -t "$IMG" "$DIR" >/dev/null
save
