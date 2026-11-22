#include "rgd_wire.h"
#include <string.h>

static unsigned be16(const uint8_t *p) { return ((unsigned)p[0] << 8) | p[1]; }
static void put16(uint8_t *p, unsigned v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }

static int valid(const uint8_t *p, size_t n) {
    size_t at = 6;
    if (!p || n < 6 || n > 65535 || p[0] != 0x40 || p[1] != 0x40 || be16(p + 2) != n) return 0;
    while (at < n) {
        unsigned len;
        if (n - at < 4) return 0;
        len = be16(p + at);
        if (len < 4 || len > n - at) return 0;
        at += len;
    }
    return 1;
}

/* Positive=expected scalar width (accepts 1..8 bytes on wire),
 * -1=text, -2=u16 list, -3=opaque structured value, 0=unknown field. */
static int field_type(unsigned msg, unsigned id) {
    if (id == 0) return -2;
    if (msg == 0x5201) {
        switch (id) {
        case 1: case 2: case 9: case 12: case 15: case 18: case 20: return 1;
        case 5: case 6: return 8;
        case 7: case 10: return 4;
        case 14: case 16: case 17: return 2;
        case 3: case 4: case 8: case 11: case 19: return -1;
        case 13: return -2;
        }
    } else if (msg == 0x5202) {
        switch (id) {
        case 1: case 11: case 12: return 2;
        case 3: case 7: case 8: case 9: return 1;
        case 5: return 4;
        case 2: case 4: case 6: case 13: return -1;
        case 10: return -2;
        }
    } else if (msg == 0x5204) {
        switch (id) { case 1: return 2; case 2: return -3; case 3: return -1; }
    } else if (msg == 0x5200) {
        switch (id) { case 1: return -1; case 2: case 3: return 1; }
    }
    return 0;
}

int rgd_parse(const uint8_t *p, size_t n, struct rgd_event *out) {
    struct rgd_event e;
    size_t at;
    if (!out || !valid(p, n)) return -1;
    if (be16(p + 4) < 0x5200 || be16(p + 4) > 0x5204) return 0;
    memset(&e, 0, sizeof(e));
    e.message = (uint16_t)be16(p + 4);
    for (at = 6; at < n;) {
        unsigned len = be16(p + at), id = be16(p + at + 2), size = len - 4;
        int type = field_type(e.message, id);
        if (!type || id >= 32) {
            e.unknown_fields++;
            at += len;
            continue;
        }
        if (e.message == 0x5200 && (id == 2 || id == 3) && !size) type = -3;
        if (type > 0 && (size < 1 || size > 8)) return -1;
        if (type == -2 && (size & 1)) return -1;
        if ((unsigned)e.length[id] + size > 65535) return -1;
        e.present |= 1u << id;
        e.length[id] = (uint16_t)size;
        if (type > 0) {
            unsigned j;
            uint64_t val = 0;
            e.numeric |= 1u << id;
            for (j = 0; j < size; j++) val = (val << 8) | p[at + 4 + j];
            e.value[id] = val;
        }
        at += len;
    }
    *out = e;
    return 1;
}

static int has_id(const uint8_t *p, size_t n, unsigned id) {
    size_t i;
    for (i = 0; i < n; i += 2) if (be16(p + i) == id) return 1;
    return 0;
}

size_t rgd_identify(const uint8_t *p, size_t n, uint16_t component, uint8_t *out, size_t cap) {
    uint8_t result[4096], group[128];
    size_t at, used = 6, g = 0;
    unsigned seen = 0;
    const unsigned send_ids[] = {0x5200, 0x5203};
    const unsigned recv_ids[] = {0x5201, 0x5202, 0x5204};
    const char name[] = "ClusterMap guidance";
    if (!out || !valid(p, n) || n > sizeof(result) - 128 || be16(p + 4) != 0x1d01) return 0;
    if ((uintptr_t)out <= (uintptr_t)p) {
        if ((uintptr_t)p - (uintptr_t)out < cap) return 0;
    } else if ((uintptr_t)out - (uintptr_t)p < n) return 0;
    memcpy(result, p, 6);
    for (at = 6; at < n;) {
        unsigned len = be16(p + at), id = be16(p + at + 2);
        if (id == 30) return 0;
        if (id == 6 || id == 7) {
            const unsigned *ids = id == 6 ? send_ids : recv_ids;
            size_t count = id == 6 ? 2 : 3, j, start = used;
            if ((len - 4) & 1 || (seen & (1u << (id - 6)))) return 0;
            seen |= 1u << (id - 6);
            if (len > sizeof(result) - used) return 0;
            memcpy(result + used, p + at, len);
            used += len;
            for (j = 0; j < count; j++) {
                if (!has_id(p + at + 4, len - 4, ids[j])) {
                    if (sizeof(result) - used < 2) return 0;
                    put16(result + used, ids[j]);
                    used += 2;
                }
            }
            put16(result + start, (unsigned)(used - start));
        } else {
            if (len > sizeof(result) - used) return 0;
            memcpy(result + used, p + at, len);
            used += len;
        }
        at += len;
    }
    if (seen != 3) return 0;
    put16(group + g, 6); put16(group + g + 2, 0); put16(group + g + 4, component); g += 6;
    put16(group + g, (unsigned)sizeof(name) + 4); put16(group + g + 2, 1);
    memcpy(group + g + 4, name, sizeof(name)); g += 4 + sizeof(name);
    for (at = 2; at <= 8; at++) {
        put16(group + g, 6);
        put16(group + g + 2, (unsigned)at);
        put16(group + g + 4, (at == 6 || at == 8) ? 16 : 96);
        g += 6;
    }
    if (g + 4 > sizeof(result) - used || used + g + 4 > cap) return 0;
    put16(result + used, (unsigned)g + 4);
    put16(result + used + 2, 30);
    memcpy(result + used + 4, group, g);
    used += g + 4;
    put16(result + 2, (unsigned)used);
    memcpy(out, result, used);
    return used;
}

