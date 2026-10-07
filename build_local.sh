#!/bin/bash
# Local build with the open QNX 6.5 ARMv7 toolchain image (luka-dev/qnx65-armv7-toolchain,
# tag 8.5) instead of the private mibsdk image the upstream Makefiles expect.
#
#   ./build_local.sh            build everything and assemble dist/sdcard
#   ./build_local.sh hook       only libgal_hook.so + libdmdt_flush.so
#   ./build_local.sh player     only stream-player (builds ffmpeg-mini on first use)
#
# Output: dist/sdcard/  -- copy its CONTENTS to the SD card root.
set -euo pipefail
IMG=${QNX_IMAGE:-qnx65-armv7-toolchain:8.5}
ROOT="$(cd "$(dirname "$0")" && pwd)"
WHAT=${1:-all}
BUILD_ID=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo local)
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "ERROR: docker image $IMG not found; build it first (qnx-run.sh build 8.5)"; exit 1; }
run() { docker run --rm --platform=linux/amd64 -v "$ROOT":/work -w /work -e BUILD_ID="$BUILD_ID" "$IMG" bash -c "$1"; }
ENVSETUP='export PATH=/opt/qnx650/host/linux/x86/usr/bin:$PATH QNX_HOST=/opt/qnx650/host/linux/x86 QNX_TARGET=/opt/qnx650/target/qnx6; P=arm-unknown-nto-qnx6.5.0eabi'
mkdir -p "$ROOT/build"

build_hook() {
  run "$ENVSETUP"'
    set -e
    # --exclude-libs,ALL keeps libgcc helpers (_Unwind_*, __aeabi_*) out of the dynamic
    # symbol table: a preloaded library must not interpose those over gal'"'"'s own.
    $P-gcc -O2 -Wall -Wextra -shared -fPIC -I./src -DGAL_HOOK_BUILD="\"$BUILD_ID\"" \
        ./src/*.c -Wl,--exclude-libs,ALL -lsocket -o build/libgal_hook.so
    $P-gcc -O2 -Wall -shared -fPIC dmdt_flush/dmdt_flush.c -Wl,--exclude-libs,ALL -o build/libdmdt_flush.so
    echo "--- exported symbols that are not ours (must be empty):"
    bad=$($P-nm -D --defined-only build/libgal_hook.so | awk "{print \$3}" | \
          grep -Ev "^(_ZN|gal_hook_|fc_|vc_|hook_fix_enabled|_init|_fini|__bss|_edata|_end|__end__|_bss_end__|__bss_start__|__bss_end__|__data_start|__exidx_start|__exidx_end|_btext|_stack)" || true)
    echo "$bad"
    [ -z "$bad" ] || { echo "REJECTED: unexpected exports"; exit 1; }
    n=$($P-nm build/libgal_hook.so | grep -ci emutls || true)
    [ "$n" = "0" ] || { echo "REJECTED: emutls symbols present"; exit 1; }
    $P-readelf -d build/libgal_hook.so | grep NEEDED
  '
}

build_player() {
  run "$ENVSETUP"'
    set -e
    FF=/work/build/ffmpeg-mini; V=6.1.5
    SHA=b8c8e926b948c14df1264cd0beac1c773df9170ac9cac97bdf1275cd3d385902
    if [ ! -f $FF/libavcodec/libavcodec.a ]; then
      cd /work/build
      [ -f ffmpeg-$V.tar.gz ] || curl -fL --retry 3 -o ffmpeg-$V.tar.gz https://ffmpeg.org/releases/ffmpeg-$V.tar.gz
      echo "$SHA  ffmpeg-$V.tar.gz" | sha256sum -c -
      mkdir -p $FF && tar xf ffmpeg-$V.tar.gz -C $FF --strip-components=1
      cd $FF
      ./configure --cc=$P-gcc --ar=$P-ar --ld=$P-gcc --nm=$P-nm --ranlib=$P-ranlib --strip=$P-strip \
        --arch=arm --target-os=qnx --disable-asm --disable-debug --enable-cross-compile \
        --extra-cflags="-D_QNX_SOURCE -include stddef.h -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16" \
        --extra-libs=-lsocket --disable-doc --disable-programs --disable-avdevice --disable-swresample \
        --disable-swscale --disable-postproc --disable-avfilter --disable-everything \
        --enable-decoder=h264 --enable-parser=h264
      make -j"$(nproc)"
    fi
    cd /work/player
    $P-g++ -O2 -Wall -DNDEBUG -I$FF -I. opengl_gpu.cc -c -o /work/build/opengl_gpu.o
    $P-g++ /work/build/opengl_gpu.o \
        -Wl,--start-group $FF/libavformat/libavformat.a $FF/libavcodec/libavcodec.a $FF/libavutil/libavutil.a -Wl,--end-group \
        -static-libstdc++ -static-libgcc -lEGL -lGLESv2 -lsocket -lm -o /work/build/stream-player
    $P-strip -s /work/build/stream-player
    $P-readelf -d /work/build/stream-player | grep NEEDED
  '
}

package() {
  D="$ROOT/dist/sdcard"; rm -rf "$D"; mkdir -p "$D/scripts" "$D/lib"
  cp "$ROOT/build/libgal_hook.so" "$ROOT/build/stream-player" "$D/"
  cp "$ROOT/build/libdmdt_flush.so" "$D/lib/"
  # The scripts treat their own directory as the card root, so they sit at the root;
  # lib_app_mount.sh is looked up in scripts/ first.
  # Layout from the upstream install guide (commit 23d63d4, dropped from the docs later).
  cp "$ROOT"/scripts/enable_hook.sh "$ROOT"/scripts/disable_hook.sh "$ROOT"/scripts/collect_logs.sh "$D/"
  cp "$ROOT/scripts/lib_app_mount.sh" "$ROOT/scripts/hook_status.sh" "$ROOT/scripts/lib_resolve_hook_log.sh" "$D/scripts/"
  cp "$ROOT/car/gal_dualscreen.conf" "$D/gal_dualscreen.conf"
  (cd "$D" && shasum -a 256 libgal_hook.so stream-player lib/libdmdt_flush.so > SHA256SUMS.txt)
  echo "Packaged: $D"; ls -la "$D" "$D/lib" "$D/scripts"
}

case "$WHAT" in
  hook) build_hook ;;
  player) build_player ;;
  all) build_hook; build_player; package ;;
  package) package ;;
  *) echo "usage: $0 [all|hook|player|package]"; exit 2 ;;
esac
