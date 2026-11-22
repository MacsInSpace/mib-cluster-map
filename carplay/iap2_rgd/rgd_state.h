#ifndef CLUSTERMAP_RGD_STATE_H
#define CLUSTERMAP_RGD_STATE_H
#include <stddef.h>
#include <stdint.h>

#define RGD_STATE_SLOTS 32
#define RGD_STATE_TEXT 128
#define RGD_STATE_EXIT 64
#define RGD_M_TYPE        (1u << 0)
#define RGD_M_DESCRIPTION (1u << 1)
#define RGD_M_ROAD        (1u << 2)
#define RGD_M_EXIT        (1u << 3)
#define RGD_M_ANGLE       (1u << 4)
#define RGD_M_STEP_DIST   (1u << 5)
#define RGD_M_DRIVING     (1u << 6)
#define RGD_M_JUNCTION    (1u << 7)

struct rgd_maneuver {
    int used;
    uint16_t index;
    unsigned present;
    uint8_t type;
    int exit_angle;
    int driving_side;
    int junction_type;
    uint32_t step_distance_m;
    char description[RGD_STATE_TEXT], road[RGD_STATE_TEXT], exit[RGD_STATE_EXIT];
};

struct rgd_state {
    uint64_t session, epoch;
    uint16_t component;
    int route_known, route_state, maneuver_state, source_support, visible_in_app;
    int order_known;
    size_t order_count;
    uint16_t order[RGD_STATE_SLOTS];
    int distance_known, eta_known, remaining_known, destination_distance_known;
    uint32_t distance_m, destination_distance_m;
    uint64_t eta_seconds, remaining_seconds;
    char current_road[RGD_STATE_TEXT], destination[RGD_STATE_TEXT], source_name[RGD_STATE_EXIT];
    struct rgd_maneuver slots[RGD_STATE_SLOTS];
};

struct rgd_current {
    struct rgd_maneuver maneuver;
    int has_maneuver;
    int distance_known;
    uint32_t distance_m;
};

void rgd_state_reset(struct rgd_state *, uint16_t component, uint64_t session, uint64_t epoch);
int rgd_state_apply(struct rgd_state *, uint64_t session, uint64_t epoch,
                    const uint8_t *, size_t);
int rgd_state_current(const struct rgd_state *, struct rgd_current *);
#endif

