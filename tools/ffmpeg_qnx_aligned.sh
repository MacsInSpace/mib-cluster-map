#!/bin/sh
# Leaves out FFmpeg's ARM NEON routines that access memory misaligned.
#
#   tools/ffmpeg_qnx_aligned.sh <ffmpeg source dir>
#
# Linux and Android let a NEON lane load or store of 16 or 32 bits land on any
# address. The head unit's QNX kernel does not: it stops the player with
# SIGBUS (1.3.0-beta2 crashed at every start, in ff_h264_h_loop_filter_luma_
# neon, "vst1.32 {d8[0]}, [r0]" at pix-2). A scan of every 16, 32 or 64-bit
# vld/vst without an alignment qualifier in the decoder's NEON files
# (h264dsp, h264cmc, h264pred, h264qpel, h264idct) finds these routines, so
# FFmpeg's C versions are used for them instead:
#   h264_h_loop_filter_luma, h264_h_loop_filter_chroma (and chroma422):
#       4-byte stores and loads at pix-2;
#   put/avg_h264_chroma_pixels_tab[1] and [2] (chroma mc4, mc2): 4- and
#       2-byte loads from any source address;
#   pred8x8[PLANE_PRED8x8] (chroma plane prediction): a 4-byte load at
#       src - stride - 1.
# Every other NEON routine of the decoder stays. Run on the source before
# configure; running it again changes nothing. Fails if an assignment it looks
# for is missing, so a new FFmpeg version is noticed.
set -e
SRC=${1:?usage: $0 <ffmpeg source dir>}
DSP="$SRC/libavcodec/arm/h264dsp_init_arm.c"
CMC="$SRC/libavcodec/arm/h264chroma_init_arm.c"
PRED="$SRC/libavcodec/arm/h264pred_init_arm.c"
for f in "$DSP" "$CMC" "$PRED"; do
    [ -f "$f" ] || { echo "ffmpeg_qnx_aligned: $f missing" >&2; exit 1; }
done
MARK="/* QNX: misaligned NEON access */"
patch_line()
{
    # patch_line FILE ASSIGNMENT: replace the assignment by an empty
    # statement (it can be the body of an if or else).
    if grep -qF "$2" "$1"; then
        # Literal text, not a pattern: the table assignments have [1] and [2].
        awk -v pat="$2" -v rep="; $MARK" '{
            i = index($0, pat)
            if (i) $0 = substr($0, 1, i - 1) rep substr($0, i + length(pat))
            print
        }' "$1" > "$1.new" && mv "$1.new" "$1"
    elif ! grep -qF "$MARK" "$1"; then
        echo "ffmpeg_qnx_aligned: '$2' not found in $1" >&2
        exit 1
    fi
}
patch_line "$DSP" "c->h264_h_loop_filter_luma   = ff_h264_h_loop_filter_luma_neon;"
patch_line "$DSP" "c->h264_h_loop_filter_chroma = ff_h264_h_loop_filter_chroma_neon;"
patch_line "$DSP" "c->h264_h_loop_filter_chroma = ff_h264_h_loop_filter_chroma422_neon;"
patch_line "$CMC" "c->put_h264_chroma_pixels_tab[1] = ff_put_h264_chroma_mc4_neon;"
patch_line "$CMC" "c->put_h264_chroma_pixels_tab[2] = ff_put_h264_chroma_mc2_neon;"
patch_line "$CMC" "c->avg_h264_chroma_pixels_tab[1] = ff_avg_h264_chroma_mc4_neon;"
patch_line "$CMC" "c->avg_h264_chroma_pixels_tab[2] = ff_avg_h264_chroma_mc2_neon;"
patch_line "$PRED" "h->pred8x8[PLANE_PRED8x8] = ff_pred8x8_plane_neon;"
left=`grep -cE "ff_h264_h_loop_filter_(luma|chroma|chroma422)_neon;|ff_(put|avg)_h264_chroma_mc[24]_neon;|ff_pred8x8_plane_neon;" "$DSP" "$CMC" "$PRED" | awk -F: '{ n += $2 } END { print n }'`
if [ "$left" != 0 ]; then
    echo "ffmpeg_qnx_aligned: $left misaligned NEON routines still assigned" >&2
    exit 1
fi
echo "ffmpeg_qnx_aligned: H.264 h loop filters, chroma mc4/mc2 and 8x8 plane prediction use C"
