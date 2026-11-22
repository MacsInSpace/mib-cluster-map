#include "rgd_state.h"
#include "rgd_wire.h"
#include <string.h>

static unsigned be16(const uint8_t *p) { return ((unsigned)p[0] << 8) | p[1]; }
static int present(const struct rgd_event *e, unsigned id) { return !!(e->present & (1u << id)); }

static const uint8_t *field(const uint8_t *p, size_t n, unsigned id, size_t *size) {
    size_t at;
    for (at = 6; at < n; at += be16(p + at)) {
        if (be16(p + at + 2) == id) {
            *size = be16(p + at) - 4;
            return p + at + 4;
        }
    }
    *size = 0;
    return NULL;
}

/* Safe UTF-8 copy with clipping at codepoint boundaries and control-char sanitization. */
static void copy_text(char *out, size_t cap, const uint8_t *p, size_t n) {
    size_t i = 0, w = 0;
    if (!out || !cap) return;
    while (n && p[n - 1] == 0) --n;
    while (i < n && w + 1 < cap) {
        unsigned c = p[i];
        if (c == 0) break;
        if (c < 0x80) {
            out[w++] = (char)((c < 0x20 || c == 0x7f || c == '=') ? ' ' : c);
            i++;
        } else {
            size_t need = (c >= 0xf0) ? 4 : (c >= 0xe0) ? 3 : (c >= 0xc2) ? 2 : 1;
            if (need == 1 || i + need > n) {
                i++;
                continue;
            }
            if (w + need >= cap) break;
            memcpy(out + w, p + i, need);
            w += need;
            i += need;
        }
    }
    out[w] = 0;
}

static void text_field(char *out, size_t cap, const uint8_t *p, size_t n, unsigned id) {
    size_t size;
    const uint8_t *value = field(p, n, id, &size);
    if (value) copy_text(out, cap, value, size);
}

void rgd_state_reset(struct rgd_state *s, uint16_t component, uint64_t session, uint64_t epoch) {
    memset(s, 0, sizeof(*s));
    s->component = component;
    s->session = session;
    s->epoch = epoch;
    s->source_support = -1;
}

static int listed(const struct rgd_state *s, unsigned index) {
    size_t i;
    for (i = 0; i < s->order_count; ++i) if (s->order[i] == index) return 1;
    return 0;
}

static struct rgd_maneuver *slot(struct rgd_state *s, uint16_t index) {
    size_t i;
    struct rgd_maneuver *free_slot = NULL, *unlisted = NULL;
    for (i = 0; i < RGD_STATE_SLOTS; ++i) {
        struct rgd_maneuver *m = &s->slots[i];
        if (m->used && m->index == index) return m;
        if (!m->used && !free_slot) free_slot = m;
        if (m->used && s->order_known && !listed(s, m->index) && !unlisted) unlisted = m;
    }
    if (!free_slot) free_slot = unlisted ? unlisted : &s->slots[RGD_STATE_SLOTS - 1];
    memset(free_slot, 0, sizeof(*free_slot));
    free_slot->used = 1;
    free_slot->index = index;
    free_slot->driving_side = -1;
    free_slot->junction_type = -1;
    return free_slot;
}

static void order_field(struct rgd_state *s, const uint8_t *p, size_t n) {
    size_t size, i, count, old_count = s->order_count;
    unsigned old_first = old_count ? s->order[0] : 0;
    const uint8_t *v = field(p, n, 13, &size);
    if (!v) return;
    count = size / 2;
    if (count > RGD_STATE_SLOTS) count = RGD_STATE_SLOTS;
    s->order_count = count;
    s->order_known = 1;
    for (i = 0; i < count; ++i) {
        s->order[i] = (uint16_t)be16(v + i * 2);
    }
    if (!s->order_count || !old_count || old_first != s->order[0]) {
        s->distance_known = 0;
        s->distance_m = 0;
    }
}

static void update_route(struct rgd_state *s, const struct rgd_event *e, const uint8_t *p, size_t n) {
    int old_support = s->source_support;
    char old_source[RGD_STATE_EXIT];
    memcpy(old_source, s->source_name, sizeof(old_source));
    if (present(e, 1)) {
        int next = (int)e->value[1];
        if ((next == 0 || next == 2) && (!s->route_known || s->route_state != next)) {
            rgd_state_reset(s, s->component, s->session, s->epoch);
            s->source_support = old_support;
            memcpy(s->source_name, old_source, sizeof(s->source_name));
        }
        s->route_known = 1;
        s->route_state = next;
    }
    if (present(e, 2)) s->maneuver_state = (int)e->value[2];
    if (present(e, 18)) s->visible_in_app = (int)e->value[18];
    if (present(e, 20)) s->source_support = e->value[20] != 0;
    text_field(s->source_name, sizeof(s->source_name), p, n, 19);
    if (s->source_support == 0 || (s->route_known && (s->route_state == 0 || s->route_state == 2))) {
        int known = s->route_known, state = s->route_state, support = s->source_support;
        memcpy(old_source, s->source_name, sizeof(old_source));
        rgd_state_reset(s, s->component, s->session, s->epoch);
        s->route_known = known;
        s->route_state = state;
        s->source_support = support;
        memcpy(s->source_name, old_source, sizeof(s->source_name));
        return;
    }
    order_field(s, p, n);
    text_field(s->current_road, sizeof(s->current_road), p, n, 3);
    text_field(s->destination, sizeof(s->destination), p, n, 4);
    if (present(e, 5)) { s->eta_known = 1; s->eta_seconds = e->value[5]; }
    if (present(e, 6)) { s->remaining_known = 1; s->remaining_seconds = e->value[6]; }
    if (present(e, 7)) { s->destination_distance_known = 1; s->destination_distance_m = (uint32_t)e->value[7]; }
    if (present(e, 10)) { s->distance_known = 1; s->distance_m = (uint32_t)e->value[10]; }
}

int rgd_state_apply(struct rgd_state *s, uint64_t session, uint64_t epoch, const uint8_t *p, size_t n) {
    struct rgd_event e;
    size_t size, i;
    const uint8_t *components;
    int rc, matches = 0;
    if (!s) return -1;
    if (session != s->session || epoch != s->epoch) return 0;
    rc = rgd_parse(p, n, &e);
    if (rc != 1) return rc;
    if (e.message != 0x5201 && e.message != 0x5202) return 0;
    components = field(p, n, 0, &size);
    if (components && size >= 2) {
        for (i = 0; i < size; i += 2) if (be16(components + i) == s->component) matches = 1;
        if (!matches) return 0;
    }
    if (e.message == 0x5201) {
        update_route(s, &e, p, n);
    } else {
        struct rgd_maneuver *m;
        if (s->source_support == 0 || (s->route_known && (s->route_state == 0 || s->route_state == 2))) return 0;
        if (!present(&e, 1)) return -1;
        m = slot(s, (uint16_t)e.value[1]);
        if (!m) return -1;
        text_field(m->description, sizeof(m->description), p, n, 2);
        text_field(m->road, sizeof(m->road), p, n, 4);
        text_field(m->exit, sizeof(m->exit), p, n, 13);
        if (present(&e, 2)) m->present |= RGD_M_DESCRIPTION;
        if (present(&e, 4)) m->present |= RGD_M_ROAD;
        if (present(&e, 13)) m->present |= RGD_M_EXIT;
        if (present(&e, 3)) { m->present |= RGD_M_TYPE; m->type = (uint8_t)e.value[3]; }
        if (present(&e, 5)) { m->present |= RGD_M_STEP_DIST; m->step_distance_m = (uint32_t)e.value[5]; }
        if (present(&e, 8)) { m->present |= RGD_M_DRIVING; m->driving_side = (int)e.value[8]; }
        if (present(&e, 9)) { m->present |= RGD_M_JUNCTION; m->junction_type = (int)e.value[9]; }
        if (present(&e, 11)) {
            unsigned angle = (unsigned)e.value[11];
            m->present |= RGD_M_ANGLE;
            m->exit_angle = angle >= 32768 ? (int)angle - 65536 : (int)angle;
        }
    }
    return 1;
}

int rgd_state_current(const struct rgd_state *s, struct rgd_current *out) {
    size_t i;
    if (!s || !out || !s->route_known || s->source_support == 0) return 0;
    if (s->route_state == 0 || s->route_state == 2) return 0;
    memset(out, 0, sizeof(*out));
    out->distance_known = s->distance_known;
    out->distance_m = s->distance_m;
    if (s->order_known && s->order_count > 0) {
        for (i = 0; i < RGD_STATE_SLOTS; ++i) {
            const struct rgd_maneuver *m = &s->slots[i];
            if (m->used && m->index == s->order[0]) {
                out->maneuver = *m;
                out->has_maneuver = 1;
                return 1;
            }
        }
    }
    /* Fallback: if order list was omitted by the app, pick the first populated slot */
    for (i = 0; i < RGD_STATE_SLOTS; ++i) {
        const struct rgd_maneuver *m = &s->slots[i];
        if (m->used && m->present != 0) {
            out->maneuver = *m;
            out->has_maneuver = 1;
            return 1;
        }
    }
    /* Active route (or rerouting) before first maneuver slot arrives */
    return 1;
}

