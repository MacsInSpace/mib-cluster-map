#include "../src/hd_frame_geometry.h"
#include "../src/video_insets_payload.h"

#include <assert.h>
#include <string.h>

int main(void)
{
    unsigned top, bottom, left, right;
    unsigned char payload[32];
    static const unsigned char expected[] = {
        0x5a, 0x0e, 0x12, 0x0c, 0x08, 0xf4, 0x02, 0x10,
        0xcf, 0x03, 0x18, 0xfa, 0x01, 0x20, 0xfa, 0x01
    };

    assert(gal_hd_frame_translate_insets(
        1920u, 1080u, 480u, 625u, 0u, 0u, 0u, 0u,
        &top, &bottom, &left, &right));
    assert(top == 312u && bottom == 313u && left == 240u && right == 240u);

    assert(gal_hd_frame_translate_insets(
        1920u, 1080u, 480u, 625u, 50u, 65u, 20u, 45u,
        &top, &bottom, &left, &right));
    assert(top == 362u && bottom == 378u && left == 260u && right == 285u);

    assert(gal_hd_frame_translate_insets(
        1280u, 720u, 270u, 344u, 0u, 0u, 0u, 0u,
        &top, &bottom, &left, &right));
    assert(top == 172u && bottom == 172u && left == 135u && right == 135u);

    assert(!gal_hd_frame_translate_insets(
        1920u, 1080u, 480u, 625u, 0x3fffu, 0u, 0u, 0u,
        &top, &bottom, &left, &right));

    assert(gal_build_insets_payload(
        payload, sizeof(payload), 372u, 463u, 250u, 250u, 0u) ==
        sizeof(expected));
    assert(memcmp(payload, expected, sizeof(expected)) == 0);
    assert(memchr(payload, '\0', sizeof(expected)) == NULL);
    assert(gal_build_insets_payload(
        payload, 15u, 372u, 463u, 250u, 250u, 0u) == 0u);
    assert(gal_build_insets_payload(
        payload, sizeof(payload), 372u, 463u, 250u, 250u, 1u) == 18u);

    return 0;
}
