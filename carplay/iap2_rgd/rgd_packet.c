#include "rgd_packet.h"
#include "rgd_wire.h"
#include <stdlib.h>
#include <string.h>
int rgd_packet_identify(struct rgd_native_packet *p, uint16_t component) {
    uint8_t *scratch, *input, *output;
    size_t old, n, limit;
    if (!p || !p->storage || !p->control || p->control != p->storage + 9 || p->capacity < 20 || p->capacity > 65535) return 0;
    /* In stock ipod-drvr-iap2.so, ident_info_request invokes ident_info_funcs[]
     * BEFORE link_send_message(ctx, pkt, 0x1D01) prepends the 6-byte control
     * header (0x40 0x40 len_hi len_lo 0x1D 0x01) at p->control[0..5].
     * Therefore, inside ident_info_funcs callbacks, p->payload_length is the TLV
     * parameter bytes starting at p->control + 6 (and p->total is 0). */
    old = p->payload_length;
    limit = p->capacity - 20;
    if (old > limit || old > 3900) return 0;
    scratch = malloc(8192);
    if (!scratch) return 0;
    input = scratch;
    output = scratch + 4096;
    input[0] = input[1] = 0x40;
    input[2] = (uint8_t)((old + 6) >> 8);
    input[3] = (uint8_t)(old + 6);
    input[4] = 0x1d;
    input[5] = 1;
    memcpy(input + 6, p->control + 6, old);
    n = rgd_identify(input, old + 6, component, output, 4096);
    if (!n || n < old + 6 || n - 6 > limit || n - 6 > 65535) {
        free(scratch);
        return 0;
    }
    memcpy(p->control + 6, output + 6, n - 6);
    if (p->total >= old) p->total += (uint32_t)(n - 6 - old);
    p->payload_length = (uint16_t)(n - 6);
    free(scratch);
    return 1;
}

