#include "rgd_monitor.h"
#include <string.h>
static unsigned u16(const uint8_t *p) { return ((unsigned)p[0] << 8) | p[1]; }
static int checksum(const uint8_t *p, size_t n) { unsigned sum = 0; while (n--) sum += *p++; return (sum & 255) == 0; }
void rgd_monitor_init(struct rgd_monitor *s, rgd_message_fn fn, void *opaque) {
    memset(s, 0, sizeof(*s));
    s->callback = fn;
    s->opaque = opaque;
}
static void control_bytes(struct rgd_monitor *s, const uint8_t *p, size_t n) {
    while (n) {
        size_t need, take;
        if (s->message_used < 6) need = 6 - s->message_used;
        else {
            unsigned size = u16(s->message + 2);
            if (s->message[0] != 0x40 || s->message[1] != 0x40 || size < 6) {
                s->message_used = 0;
                s->gaps++;
                return;
            }
            need = size - s->message_used;
        }
        take = need < n ? need : n;
        memcpy(s->message + s->message_used, p, take);
        s->message_used += take;
        p += take;
        n -= take;
        if (s->message_used >= 6) {
            unsigned size = u16(s->message + 2);
            if (s->message[0] != 0x40 || s->message[1] != 0x40 || size < 6) {
                s->message_used = 0;
                s->gaps++;
                return;
            }
            if (s->message_used == size) {
                s->messages++;
                if (s->callback) s->callback(s->opaque, s->message, size);
                s->message_used = 0;
            }
        }
    }
}
static void packet(struct rgd_monitor *s) {
    uint8_t *p = s->packet;
    size_t n = s->wanted;
    unsigned flags = p[4], seq = p[5], sid = p[7];
    if (n > 9 && !checksum(p + 9, n - 9)) { s->bad_packets++; s->message_used = 0; return; }
    s->packets++;
    if (flags & 0x10) { s->message_used = 0; s->control_known = s->sequence_known = 0; return; }
    if (flags & 0x80) {
        size_t at, payload = n > 9 ? n - 10 : 0;
        s->message_used = 0;
        s->control_known = s->sequence_known = 0;
        if (payload < 10 || p[9] != 1 || (payload - 10) % 3) return;
        for (at = 19; at < 9 + payload; at += 3) {
            if (p[at + 1] == 0) { s->control_known = 1; s->control_id = p[at]; break; }
        }
        return;
    }
    if (n <= 10 || (flags & 0x20)) return;
    if (s->sequence_known && seq == s->sequence) { s->duplicates++; return; }
    if (s->sequence_known && seq != ((s->sequence + 1) & 255)) { s->message_used = 0; s->gaps++; }
    s->sequence_known = 1;
    s->sequence = seq;
    if (s->control_known && sid == s->control_id) control_bytes(s, p + 9, n - 10);
}
void rgd_monitor_feed(struct rgd_monitor *s, const void *data, size_t n) {
    const uint8_t *p = data;
    if (!s || (!data && n)) return;
    while (n--) {
        uint8_t v = *p++;
        if (s->used == 0) { if (v == 0xff) s->packet[s->used++] = v; continue; }
        if (s->used == 1) { if (v == 0x5a) s->packet[s->used++] = v; else s->used = v == 0xff ? 1 : 0; continue; }
        s->packet[s->used++] = v;
        if (s->used == 9) {
            s->wanted = u16(s->packet + 2);
            if (s->wanted < 9 || !checksum(s->packet, 9)) { s->used = s->wanted = 0; s->message_used = 0; s->bad_packets++; continue; }
        }
        if (s->wanted && s->used == s->wanted) { packet(s); s->used = s->wanted = 0; }
    }
}

