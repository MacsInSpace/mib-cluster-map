#!/bin/sh
# Compiler wrapper for building FFmpeg with its NEON code for QNX 6.5
# (from AMDFX60's Skoda fork of this project, car-tested on a Superb).
# FFmpeg's C files need stddef.h forced in on QNX 6.5 (size_t and friends);
# its assembly must not get it, or configure finds no working assembler and
# NEON stays off. build_local.sh copies this next to the FFmpeg source.
CC=${QNX_CC:-arm-unknown-nto-qnx6.5.0eabi-gcc}
for a in "$@"; do
    case "$a" in
        *.c) exec "$CC" -include stddef.h "$@" ;;
    esac
done
exec "$CC" "$@"
