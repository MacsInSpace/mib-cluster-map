#ifndef GAL_HD_FRAME_GEOMETRY_H
#define GAL_HD_FRAME_GEOMETRY_H

static inline int gal_hd_frame_translate_insets(
    unsigned frame_width, unsigned frame_height,
    unsigned margin_width, unsigned margin_height,
    unsigned top, unsigned bottom, unsigned left, unsigned right,
    unsigned *stream_top, unsigned *stream_bottom,
    unsigned *stream_left, unsigned *stream_right)
{
    unsigned crop_left;
    unsigned crop_right;
    unsigned crop_top;
    unsigned crop_bottom;

    if (frame_width == 0u || frame_height == 0u ||
        margin_width >= frame_width || margin_height >= frame_height ||
        stream_top == 0 || stream_bottom == 0 ||
        stream_left == 0 || stream_right == 0) {
        return 0;
    }

    crop_left = margin_width / 2u;
    crop_right = margin_width - crop_left;
    crop_top = margin_height / 2u;
    crop_bottom = margin_height - crop_top;

    if (crop_left > 0x3fffu || crop_right > 0x3fffu ||
        crop_top > 0x3fffu || crop_bottom > 0x3fffu ||
        top > 0x3fffu - crop_top ||
        bottom > 0x3fffu - crop_bottom ||
        left > 0x3fffu - crop_left ||
        right > 0x3fffu - crop_right) {
        return 0;
    }

    *stream_top = crop_top + top;
    *stream_bottom = crop_bottom + bottom;
    *stream_left = crop_left + left;
    *stream_right = crop_right + right;
    return 1;
}

#endif
