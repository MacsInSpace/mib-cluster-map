#!/bin/sh
# Cross-compiles the minimal static FFmpeg ("ffmpeg-mini") that
# player/Makefile links stream-player against: libavcodec (H.264 decode
# only), libavformat and libavutil, built for QNX 6.5.0 / Tegra 3 ARMv7
# with the MIB SDK's GCC 4.4.2 cross compiler.
#
# stream-player talks to the network itself with raw BSD sockets
# (see opengl_gpu.cc) and only calls into libavcodec's H.264
# decoder/parser, so avformat's demuxers/protocols and avutil's
# scaling/resampling helpers are all left disabled to keep the build
# small and to avoid QNX portability problems in code paths that are
# never exercised.
#
# Must run *inside* the MIB SDK Docker image (registry.gitlab.com/
# andrewleech/mibsdk) since it needs the QNX 6.5.0 ARMv7 cross
# toolchain and headers from /etc/qnx/env. Normally you don't
# call this directly -- `make` in this directory builds ffmpeg-mini
# automatically the first time it's needed. To force a rebuild, remove
# the output directory ($FFMPEG_PATH, default player/build/ffmpeg-mini)
# or run `make ffmpeg-clean`.
set -e

# 6.1.5 is the release stream-player has been tested with on the head unit
# (VcMOSTRenderMqb's ffmpeg-instructions use it too). Its tarball is pinned
# by SHA-256; set FFMPEG_SHA256 as well when overriding FFMPEG_VERSION.
FFMPEG_VERSION="${FFMPEG_VERSION:-6.1.5}"
FFMPEG_SHA256="${FFMPEG_SHA256:-b8c8e926b948c14df1264cd0beac1c773df9170ac9cac97bdf1275cd3d385902}"
# .tar.gz, not .tar.xz/.tar.bz2: the mibsdk image only ships gzip, which
# GNU tar decompresses internally (via zlib) without needing an xz/bzip2
# binary on PATH.
FFMPEG_SRC_URL="${FFMPEG_SRC_URL:-https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz}"
TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.gz"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build}"
PREFIX="${FFMPEG_PATH:-${BUILD_DIR}/ffmpeg-mini}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

if [ ! -f /etc/qnx/env ]; then
    echo "!! build_ffmpeg.sh must run inside the mibsdk Docker image (missing /etc/qnx/env)." >&2
    echo "   Use 'make' or 'make ffmpeg' from player/ -- it wraps this script in Docker." >&2
    exit 1
fi
# shellcheck disable=SC1091
. /etc/qnx/env

# /etc/qnx/env pre-sets CC/CXX to the armle-nVidiaTegra-nto-qnx6.5.0-gcc
# toolchain and CFLAGS to "-static -static-libgcc" for it, and ffmpeg's
# ./configure appends $CFLAGS/$LDFLAGS from the environment regardless of
# the --cc below. The toolchain and flags are passed explicitly, so drop
# all of it.
unset CC CXX CFLAGS CXXFLAGS LDFLAGS

if [ -f "${PREFIX}/libavcodec/libavcodec.a" ] && \
   [ -f "${PREFIX}/libavformat/libavformat.a" ] && \
   [ -f "${PREFIX}/libavutil/libavutil.a" ]; then
    echo "==> ffmpeg-mini already built at ${PREFIX}, skipping (remove it to force a rebuild)"
    exit 0
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [ ! -f "${TARBALL}" ]; then
    echo "==> Downloading FFmpeg ${FFMPEG_VERSION} sources..."
    # Download under a temporary name, so an interrupted transfer is
    # fetched again next time instead of being taken for the tarball.
    curl -fL --retry 3 -o "${TARBALL}.part" "${FFMPEG_SRC_URL}"
    mv "${TARBALL}.part" "${TARBALL}"
fi
if ! echo "${FFMPEG_SHA256}  ${TARBALL}" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "${TARBALL}"
    echo "!! ${TARBALL} does not match FFMPEG_SHA256 (${FFMPEG_SHA256}); deleted it." >&2
    echo "   If you changed FFMPEG_VERSION, set FFMPEG_SHA256 to that tarball's SHA-256." >&2
    exit 1
fi

# player/Makefile compiles opengl_gpu.cc with "-I$(FFMPEG_PATH)" and it
# does #include <libavcodec/avcodec.h>, i.e. it expects PREFIX itself to
# be an FFmpeg *build* tree, where each library's public headers sit
# next to its .a (libavcodec/avcodec.h beside libavcodec/libavcodec.a,
# etc.) -- not a `make install` tree, which splits headers into
# PREFIX/include and would break that -I. So we build FFmpeg directly
# inside PREFIX and never run `make install`. PREFIX can already exist
# but be empty (player/Makefile bind-mounts it), so test for the sources.
if [ ! -f "${PREFIX}/configure" ]; then
    echo "==> Extracting FFmpeg ${FFMPEG_VERSION} into ${PREFIX}..."
    mkdir -p "${PREFIX}"
    tar xf "${TARBALL}" -C "${PREFIX}" --strip-components=1
fi

cd "${PREFIX}"

# ffmpeg's configure adds -O3 and its other GCC-specific flags only when it
# recognises the compiler, i.e. when "$cc -v" prints a line starting with
# "gcc". qcc never does (and without -EL, "qcc -Vgcc_ntoarmv7" is not even a
# valid target), so a qcc build leaves libavcodec unoptimised. Call the SDK's
# GCC driver directly instead, with the ARMv7/VFPv3-D16 flags that qcc's
# gcc_ntoarmv7le variant adds. These are the configure options of the
# ffmpeg-mini that stream-player was developed against.
TOOLCHAIN_BIN="${QNX_HOST}/usr/bin"

echo "==> Configuring ffmpeg-mini (H.264 decode only) for QNX 6.5.0 / ARMv7..."
./configure \
    --cc="${TOOLCHAIN_BIN}/ntoarmv7-gcc" \
    --ar="${TOOLCHAIN_BIN}/ntoarmv7-ar" \
    --ld="${TOOLCHAIN_BIN}/ntoarmv7-gcc" \
    --arch=arm \
    --target-os=qnx \
    --disable-asm \
    --disable-debug \
    --enable-cross-compile \
    --extra-cflags='-D_QNX_SOURCE -I/usr/qnx650/target/qnx6/usr/include -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16' \
    --extra-ldflags=-L/usr/qnx650/target/qnx6/armle-v7/usr/lib \
    --extra-libs=-lsocket \
    --disable-doc \
    --disable-programs \
    --disable-avdevice \
    --disable-swresample \
    --disable-swscale \
    --disable-postproc \
    --disable-avfilter \
    --disable-everything \
    --enable-decoder=h264 \
    --enable-parser=h264

make -j"${JOBS}"

echo "==> ffmpeg-mini built: ${PREFIX}"
echo "    ${PREFIX}/libavcodec/libavcodec.a"
echo "    ${PREFIX}/libavformat/libavformat.a"
echo "    ${PREFIX}/libavutil/libavutil.a"
