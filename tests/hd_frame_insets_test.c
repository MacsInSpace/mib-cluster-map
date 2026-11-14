#include "../src/hd_frame_geometry.h"

#include <assert.h>

int main(void)
{
    unsigned top, bottom, left, right;

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

    return 0;
}
