/*
 * nav_translate.c -- Android Auto 1.6+ navigation, spoken to a 1.2 receiver.
 *
 * At protocol 1.6 and above (GAL_DUALSCREEN_AAP_MINOR) Google Maps stops
 * sending 0x8004 NavigationNextTurnEvent / 0x8005 NavigationNextTurnDistance
 * and sends 0x8006 NavigationState / 0x8007 NavigationCurrentPosition
 * instead. This unit's receiver was built against 1.2, answers the new pair
 * with -253, and the turn-arrows jar never hears of the route (#4). That is
 * why the shipped setting is 1.5.
 *
 * Here the new pair is decoded and re-encoded as the old one, in place, so
 * the stock NavigationStatusEndpoint and everything behind it (the arrows
 * jar, the cockpit's own turn pictograms) see what they always saw.
 *
 * The 1.7 schema and the manoeuvre table come from kkrvch's
 * mib-std2-kombibridge (shim/src/navproto.h), which reads the same messages
 * on MIB2 Standard units; its author invited reuse in that project's issue
 * #5. The legacy field numbers are this unit's own, read from the
 * k*FieldNumber symbols in libautoreceiver.so:
 *
 *   0x8004 NavigationNextTurnEvent  road=1 (string) turnSide=2 event=3
 *                                   image=4 turnNumber=5 turnAngle=6
 *   0x8005 NavigationNextTurnDistanceEvent  distanceMeters=1 timeToTurnSeconds=2
 *   0x8003 NavigationStatus         status=1 (0 unavailable, 1 active, 2 inactive)
 *
 * No libc beyond memcpy, so tests/nav_translate_test.c runs it on a host.
 */
#include <string.h>
#include "nav_translate.h"

static nav_translate_info g_last;

const nav_translate_info *nav_translate_last(void) { return &g_last; }

/* ---- a bounded protobuf reader ------------------------------------------ */
typedef struct { const unsigned char *p, *e; } pb;

static unsigned pb_var(pb *s)
{
    unsigned v = 0u;
    int sh = 0;
    while (s->p < s->e) {
        unsigned char b = *s->p++;
        if (sh <= 28) v |= (unsigned)(b & 0x7fu) << sh;
        if (!(b & 0x80u)) break;
        sh += 7;
    }
    return v;   /* a 10-byte negative saturates; callers range-check */
}

static int pb_tag(pb *s, unsigned *f, unsigned *w)
{
    unsigned t;
    if (s->p >= s->e) return 0;
    t = pb_var(s);
    if (t == 0u) return 0;
    *f = t >> 3;
    *w = t & 7u;
    return 1;
}

static int pb_sub(pb *s, pb *o)
{
    unsigned n = pb_var(s);
    if (n > (unsigned)(s->e - s->p)) return 0;
    o->p = s->p;
    o->e = s->p + n;
    s->p += n;
    return 1;
}

static void pb_skip(pb *s, unsigned w)
{
    unsigned left = (unsigned)(s->e - s->p), n;
    if (w == 0u) { (void)pb_var(s); return; }
    if (w == 2u) { n = pb_var(s); left = (unsigned)(s->e - s->p); s->p += n < left ? n : left; return; }
    if (w == 5u) { s->p += left >= 4u ? 4u : left; return; }
    if (w == 1u) { s->p += left >= 8u ? 8u : left; return; }
    s->p = s->e;  /* unknown wire type: stop rather than run off the end */
}

/* A string field, cut to fit, without the newlines a cockpit line cannot show. */
static unsigned pb_str(pb *s, char *dst, unsigned cap)
{
    unsigned n = pb_var(s), i, j = 0u;
    if (n > (unsigned)(s->e - s->p)) n = (unsigned)(s->e - s->p);
    for (i = 0u; i < n; ++i) {
        char c = (char)s->p[i];
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
        if (j + 1u < cap) dst[j++] = c;
    }
    dst[j] = '\0';
    s->p += n;
    return j;
}

/* ---- a protobuf writer -------------------------------------------------- */
typedef struct { unsigned char *p; unsigned n, cap; int full; } pw;

static void pw_byte(pw *o, unsigned char b)
{
    if (o->n < o->cap) o->p[o->n++] = b;
    else o->full = 1;
}

static void pw_var(pw *o, unsigned v)
{
    while (v >= 0x80u) { pw_byte(o, (unsigned char)(v | 0x80u)); v >>= 7; }
    pw_byte(o, (unsigned char)v);
}

static void pw_uint(pw *o, unsigned field, unsigned v)
{
    pw_var(o, field << 3);
    pw_var(o, v);
}

static void pw_string(pw *o, unsigned field, const char *str, unsigned len)
{
    unsigned i;
    pw_var(o, (field << 3) | 2u);
    pw_var(o, len);
    for (i = 0u; i < len; ++i) pw_byte(o, (unsigned char)str[i]);
}

/* ---- 1.7 NavigationType (1..50) -> the 1.2 event and side ----------------
 * kombibridge's table, with its jar-internal numbers for the last three
 * events changed to this receiver's wire values: FERRY_BOAT 16,
 * FERRY_TRAIN 17, DESTINATION 19. Side: 1 left, 2 right, 3 unspecified.
 * Counter-clockwise roundabouts map to RIGHT, as the 1.2 feed sent them. */
#define MV(e, s) (unsigned char)(((e) << 2) | (s))
#define N_MANEUVER 51
static const unsigned char k_maneuver[N_MANEUVER] = {
    MV(0, 3),                                   /*  0 invalid */
    MV(1, 3), MV(2, 3),                         /*  1 DEPART, 2 NAME_CHANGE */
    MV(9, 1), MV(9, 2),                         /*  3 KEEP_LEFT/RIGHT -> FORK */
    MV(3, 1), MV(3, 2),                         /*  5 TURN_SLIGHT_L/R */
    MV(4, 1), MV(4, 2),                         /*  7 TURN_NORMAL_L/R */
    MV(5, 1), MV(5, 2),                         /*  9 TURN_SHARP_L/R */
    MV(6, 1), MV(6, 2),                         /* 11 U_TURN_L/R */
    MV(7, 1), MV(7, 2), MV(7, 1), MV(7, 2),     /* 13 ON_RAMP slight, normal */
    MV(7, 1), MV(7, 2), MV(6, 1), MV(6, 2),     /* 17 ON_RAMP sharp, u-turn */
    MV(8, 1), MV(8, 2), MV(8, 1), MV(8, 2),     /* 21 OFF_RAMP slight, normal */
    MV(9, 1), MV(9, 2),                         /* 25 FORK_L/R */
    MV(10, 1), MV(10, 2), MV(10, 3),            /* 27 MERGE_L/R/unspecified */
    MV(0, 3), MV(0, 3),                         /* 30, 31 unassigned */
    MV(13, 1), MV(13, 1), MV(13, 2), MV(13, 2), /* 32 ROUNDABOUT_ENTER_AND_EXIT CW/CCW */
    MV(14, 3),                                  /* 36 STRAIGHT */
    MV(16, 3), MV(17, 3),                       /* 37 FERRY_BOAT, FERRY_TRAIN */
    MV(19, 3), MV(19, 3), MV(19, 1), MV(19, 2), /* 39 DESTINATION{,_STRAIGHT,_LEFT,_RIGHT} */
    MV(11, 1), MV(12, 1), MV(11, 2), MV(12, 2), /* 43 ROUNDABOUT ENTER/EXIT CW, CCW */
    MV(16, 1), MV(16, 2), MV(17, 1), MV(17, 2)  /* 47 FERRY_BOAT_L/R, FERRY_TRAIN_L/R */
};

#define ROAD_MAX 64u

typedef struct {
    unsigned event, side, number, angle, road_len;
    char road[ROAD_MAX];
} turn;

static void parse_maneuver(pb s, turn *t)
{
    unsigned f, w, v;
    while (pb_tag(&s, &f, &w)) {
        if (f == 1u && w == 0u) {
            unsigned char m;
            v = pb_var(&s);
            m = v < N_MANEUVER ? k_maneuver[v] : k_maneuver[0];
            t->event = (unsigned)(m >> 2);
            t->side = (unsigned)(m & 3u);
        } else if (f == 2u && w == 0u) {
            v = pb_var(&s);
            t->number = (v >= 1u && v <= 99u) ? v : 0u;
        } else if (f == 3u && w == 0u) {
            v = pb_var(&s);
            t->angle = (v >= 1u && v <= 360u) ? v : 0u;
        } else {
            pb_skip(&s, w);
        }
    }
}

/* NavigationStep { maneuver=1; instruction=2 {text=1}; lanes=3; road_info=4 {road_names=1} }.
 * The road name wins over the spoken instruction, whatever order they come in. */
static void parse_step(pb s, turn *t)
{
    char cue[ROAD_MAX];
    unsigned cue_len = 0u, f, w;
    cue[0] = '\0';
    t->event = 0u; t->side = 3u; t->number = 0u; t->angle = 0u;
    t->road[0] = '\0'; t->road_len = 0u;
    while (pb_tag(&s, &f, &w)) {
        pb d;
        unsigned df, dw;
        if (w != 2u) { pb_skip(&s, w); continue; }
        if (!pb_sub(&s, &d)) break;
        if (f == 1u) {
            parse_maneuver(d, t);
        } else if (f == 2u) {
            while (pb_tag(&d, &df, &dw)) {
                if (df == 1u && dw == 2u) cue_len = pb_str(&d, cue, sizeof cue);
                else pb_skip(&d, dw);
            }
        } else if (f == 4u) {
            while (pb_tag(&d, &df, &dw)) {
                if (df == 1u && dw == 2u && t->road_len == 0u)
                    t->road_len = pb_str(&d, t->road, sizeof t->road);
                else pb_skip(&d, dw);
            }
        }
    }
    if (t->road_len == 0u && cue_len > 0u) {
        memcpy(t->road, cue, cue_len + 1u);
        t->road_len = cue_len;
    }
}

/* Distances survive between messages: an "unknown" 0x8007 keeps the last
 * good countdown on the cockpit instead of blanking it. */
static unsigned g_meters, g_seconds;
static int g_have_distance;

/* NavigationCurrentPosition { step=1 { distance=1 { meters=1 }; time_to_step_seconds=2 } } */
static int parse_position(pb s)
{
    unsigned f, w, df, dw, nf, nw, v;
    int got = 0;
    while (pb_tag(&s, &f, &w)) {
        pb d, n;
        if (!(f == 1u && w == 2u)) { pb_skip(&s, w); continue; }
        if (!pb_sub(&s, &d)) break;
        while (pb_tag(&d, &df, &dw)) {
            if (df == 1u && dw == 2u) {
                if (!pb_sub(&d, &n)) break;
                while (pb_tag(&n, &nf, &nw)) {
                    if (nf == 1u && nw == 0u) {
                        v = pb_var(&n);
                        /* -1 ("unknown") arrives as a saturated varint */
                        if (v <= 20000000u) { g_meters = v; got = 1; }
                    } else {
                        pb_skip(&n, nw);
                    }
                }
            } else if (df == 2u && dw == 0u) {
                v = pb_var(&d);
                if (v <= 1000000u) { g_seconds = v; got = 1; }
            } else {
                pb_skip(&d, dw);
            }
        }
    }
    if (got) g_have_distance = 1;
    return g_have_distance;
}

int nav_translate(const unsigned char *in, unsigned in_len,
                  unsigned char *out, unsigned out_cap)
{
    unsigned id, f, w;
    pb s;
    pw o;

    if (in == NULL || in_len < 2u) return NAV_TRANSLATE_PASS;
    id = ((unsigned)in[0] << 8) | in[1];
    s.p = in + 2;
    s.e = in + in_len;
    o.p = out;
    o.n = 0u;
    o.cap = out_cap < in_len ? out_cap : in_len;   /* must fit over the original */
    o.full = 0;
    memset(&g_last, 0, sizeof g_last);
    g_last.from_id = id;
    g_last.status = -1;

    if (id == 0x8006u) {
        /* NavigationState { repeated NavigationStep steps=1; ... }: the first step is the next turn */
        turn t;
        int have = 0;
        while (pb_tag(&s, &f, &w)) {
            if (f == 1u && w == 2u && !have) {
                pb d;
                if (!pb_sub(&s, &d)) break;
                parse_step(d, &t);
                have = 1;
            } else {
                pb_skip(&s, w);
            }
        }
        if (!have) return NAV_TRANSLATE_DROP;
        pw_byte(&o, 0x80u);
        pw_byte(&o, 0x04u);
        if (t.road_len > 0u) pw_string(&o, 1u, t.road, t.road_len);
        pw_uint(&o, 2u, t.side);
        pw_uint(&o, 3u, t.event);
        if (t.number > 0u) pw_uint(&o, 5u, t.number);
        if (t.angle > 0u) pw_uint(&o, 6u, t.angle);
        if (o.full) return NAV_TRANSLATE_PASS;
        g_last.to_id = 0x8004u;
        g_last.event = t.event;
        g_last.side = t.side;
        g_last.road_len = t.road_len;
        return (int)o.n;
    }
    if (id == 0x8007u) {
        if (!parse_position(s)) return NAV_TRANSLATE_DROP;
        pw_byte(&o, 0x80u);
        pw_byte(&o, 0x05u);
        pw_uint(&o, 1u, g_meters);
        pw_uint(&o, 2u, g_seconds);
        if (o.full) return NAV_TRANSLATE_PASS;
        g_last.to_id = 0x8005u;
        g_last.meters = g_meters;
        g_last.seconds = g_seconds;
        return (int)o.n;
    }
    if (id == 0x8003u) {
        /* 1.7 adds status 3, REROUTING, which the 1.2 enum stops short of.
         * During a recalculation the route is still on: call it ACTIVE. */
        while (pb_tag(&s, &f, &w)) {
            if (f == 1u && w == 0u) {
                unsigned v = pb_var(&s);
                if (v != 3u) return NAV_TRANSLATE_PASS;
                pw_byte(&o, 0x80u);
                pw_byte(&o, 0x03u);
                pw_uint(&o, 1u, 1u);
                if (o.full) return NAV_TRANSLATE_PASS;
                g_last.to_id = 0x8003u;
                g_last.status = 1;
                return (int)o.n;
            }
            pb_skip(&s, w);
        }
        return NAV_TRANSLATE_PASS;
    }
    return NAV_TRANSLATE_PASS;
}
