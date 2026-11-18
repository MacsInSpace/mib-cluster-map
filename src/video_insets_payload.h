#ifndef GAL_VIDEO_INSETS_PAYLOAD_H
#define GAL_VIDEO_INSETS_PAYLOAD_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

static inline size_t gal_encode_varint(unsigned char *buf, uint32_t val)
{
    size_t len = 0u;
    while (val >= 0x80u) {
        buf[len++] = (unsigned char)((val & 0x7fu) | 0x80u);
        val >>= 7;
    }
    buf[len++] = (unsigned char)(val & 0x7fu);
    return len;
}

static inline size_t gal_build_insets_payload(unsigned char *out, size_t max_out,
                                               uint32_t top, uint32_t bottom,
                                               uint32_t left, uint32_t right,
                                               uint32_t ui_theme)
{
    unsigned char insets[16];
    size_t insets_len = 0u;
    unsigned char uiconfig[24];
    size_t uiconfig_len = 0u;
    size_t total_len = 0u;

    if (top > 0x3fffu || bottom > 0x3fffu ||
        left > 0x3fffu || right > 0x3fffu) {
        return 0u;
    }
    if (top > 0u) {
        insets[insets_len++] = 0x08;
        insets_len += gal_encode_varint(insets + insets_len, top);
    }
    if (bottom > 0u) {
        insets[insets_len++] = 0x10;
        insets_len += gal_encode_varint(insets + insets_len, bottom);
    }
    if (left > 0u) {
        insets[insets_len++] = 0x18;
        insets_len += gal_encode_varint(insets + insets_len, left);
    }
    if (right > 0u) {
        insets[insets_len++] = 0x20;
        insets_len += gal_encode_varint(insets + insets_len, right);
    }

    uiconfig[uiconfig_len++] = 0x12;
    uiconfig_len += gal_encode_varint(uiconfig + uiconfig_len,
                                      (uint32_t)insets_len);
    memcpy(uiconfig + uiconfig_len, insets, insets_len);
    uiconfig_len += insets_len;

    if (ui_theme == 1u || ui_theme == 2u) {
        uiconfig[uiconfig_len++] = 0x20;
        uiconfig[uiconfig_len++] = (unsigned char)ui_theme;
    }

    out[total_len++] = 0x5a;
    total_len += gal_encode_varint(out + total_len, (uint32_t)uiconfig_len);
    if (total_len + uiconfig_len > max_out) return 0u;
    memcpy(out + total_len, uiconfig, uiconfig_len);
    return total_len + uiconfig_len;
}

#endif
