#!/bin/sh
# Build ipod-drvr-iap2.so: the QNX ARMv7 iAP2 route-guidance proxy for MHI2.
#
#   carplay/iap2_rgd/build.sh [output dir]      default: build/ at repo root
#
# Uses Apple clang (or armv7 clang) with the QNX 6.5 SDP headers to compile
# PIC ARMv7 object files, and QNX's arm-unknown-nto-qnx6.5.0eabi-ld (in the
# local qnx-sdp Docker image) to link with -soname libclustermap_rgd_proxy.so
# and -Bsymbolic so dlopen(ipod-drvr-iap2.stock.so) never aliases the proxy.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${1:-"$ROOT/build"}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

QNX_TARGET=${QNX_TARGET:-/tmp/qnx65-armv7-toolchain/sdp/target/qnx6}
[ -d "$QNX_TARGET/usr/include" ] || {
    echo "ERROR: QNX 6.5 headers not found at $QNX_TARGET/usr/include" >&2
    exit 1
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

CFLAGS="-target armv7-unknown-linux-gnueabi -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -mno-unaligned-access -fPIC -O2 -std=gnu99 -Wall -Wextra -Werror -fno-stack-protector -fno-builtin -nostdinc -isystem $QNX_TARGET/usr/include -D__QNX__ -D__QNXNTO__ -D__ARM__ -D__ARMEL__ -D__LITTLEENDIAN__ -D_QNX_SOURCE -DRGD_ADAPTER"

for s in driver_probe rgd_adapter rgd_wire rgd_monitor rgd_packet rgd_state; do
    clang $CFLAGS -c "$HERE/$s.c" -o "$T/$s.o"
done

docker run --rm --platform=linux/amd64 \
    -v "$T:/work" -v "$OUT:/out" qnx-sdp:latest sh -e -c '
    export QNX_HOST=/opt/qnx650/host/linux/x86
    export QNX_TARGET=/opt/qnx650/target/qnx6
    LD="$QNX_HOST/usr/bin/arm-unknown-nto-qnx6.5.0eabi-ld"
    READELF="$QNX_HOST/usr/bin/arm-unknown-nto-qnx6.5.0eabi-readelf"
    "$LD" -m armnto -shared -Bsymbolic -soname libclustermap_rgd_proxy.so \
        -o /out/ipod-drvr-iap2.so \
        "$QNX_TARGET/armle-v7/lib/crti.o" "$QNX_TARGET/armle-v7/lib/crtbegin.o" \
        /work/driver_probe.o /work/rgd_adapter.o /work/rgd_wire.o \
        /work/rgd_monitor.o /work/rgd_packet.o /work/rgd_state.o \
        -L"$QNX_TARGET/armle-v7/lib" -lc \
        "$QNX_TARGET/armle-v7/lib/crtend.o" "$QNX_TARGET/armle-v7/lib/crtn.o"
    "$READELF" -d -s /out/ipod-drvr-iap2.so > /work/readelf.txt
    grep -q "Library soname: \[libclustermap_rgd_proxy.so\]" /work/readelf.txt
    grep -q "OBJECT  GLOBAL DEFAULT.*ipod_module" /work/readelf.txt
    ! grep -q "emutls" /work/readelf.txt
'
chmod 755 "$OUT/ipod-drvr-iap2.so"
echo "Built $OUT/ipod-drvr-iap2.so ($(wc -c < "$OUT/ipod-drvr-iap2.so" | tr -d ' ') bytes)"
