#ifndef CLUSTERMAP_RGD_WIRE_H
#define CLUSTERMAP_RGD_WIRE_H
#include <stddef.h>
#include <stdint.h>

struct rgd_event {
    uint16_t message;
    uint32_t present, numeric;
    uint64_t value[32];
    uint16_t length[32];
    unsigned unknown_fields;
};

/* 1=guidance event, 0=other message, -1=malformed message. */
int rgd_parse(const uint8_t *frame, size_t size, struct rgd_event *out);

/* Append iAP2 route guidance declarations (0x5200..0x5204) and component 30
 * to an IdentificationInformation (0x1D01) message. Returns 0 on failure. */
size_t rgd_identify(const uint8_t *frame, size_t size, uint16_t component,
                    uint8_t *out, size_t capacity);
#endif

