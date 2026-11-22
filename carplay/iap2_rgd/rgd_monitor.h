#ifndef CLUSTERMAP_RGD_MONITOR_H
#define CLUSTERMAP_RGD_MONITOR_H
#include <stddef.h>
#include <stdint.h>
typedef void (*rgd_message_fn)(void *, const uint8_t *, size_t);
struct rgd_monitor {
    uint8_t packet[65535], message[65535];
    size_t used, wanted, message_used;
    unsigned control_known, control_id, sequence_known, sequence;
    unsigned packets, bad_packets, gaps, duplicates, messages;
    rgd_message_fn callback;
    void *opaque;
};
void rgd_monitor_init(struct rgd_monitor *, rgd_message_fn, void *);
void rgd_monitor_feed(struct rgd_monitor *, const void *, size_t);
#endif

