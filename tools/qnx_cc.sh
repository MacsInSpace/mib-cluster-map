#!/bin/sh
# Compiler wrapper for building FFmpeg with its NEON routines for QNX 6.5.
# build_local.sh copies it next to the FFmpeg source and uses it as both the
# C compiler and the assembler.
#   C files:   stddef.h forced in (QNX 6.5 needs it for size_t and friends),
#              and the FPU left as the build sets it (VFPv3-D16), so the
#              compiler itself never emits a NEON instruction.
#   Assembly:  -mfpu=neon, so FFmpeg's hand-written NEON files assemble. No
#              stddef.h there, or configure finds no working assembler.
# The player can therefore switch every NEON instruction off at run time
# (av_force_cpu_flags), which a NEON-compiled C file would not obey.
# First version from AMDFX60's Skoda fork of this project.
CC=${QNX_CC:-arm-unknown-nto-qnx6.5.0eabi-gcc}
for a in "$@"; do
    case "$a" in
        *.c) exec "$CC" -include stddef.h "$@" ;;
        *.S) exec "$CC" "$@" -mfpu=neon ;;
    esac
done
exec "$CC" "$@"
