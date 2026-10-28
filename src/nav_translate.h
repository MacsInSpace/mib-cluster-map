#ifndef NAV_TRANSLATE_H
#define NAV_TRANSLATE_H

/*
 * Android Auto 1.6+ navigation messages, translated into the 1.2 ones this
 * unit's receiver understands (issue #4). See nav_translate.c.
 */

/* Internal to the hook: never exported, so nothing in gal can bind to it. */
#define NAV_TRANSLATE_HIDDEN __attribute__((visibility("hidden")))

#define NAV_TRANSLATE_PASS (-1)  /* leave the message as it is */
#define NAV_TRANSLATE_DROP 0     /* nothing usable: do not route it */

/*
 * in/in_len: the whole message, starting with its two-byte id.
 * Returns NAV_TRANSLATE_PASS, NAV_TRANSLATE_DROP, or the length of the
 * translated message written to out (with its own id), never more than
 * in_len, so the caller can write it over the original.
 */
NAV_TRANSLATE_HIDDEN int nav_translate(const unsigned char *in, unsigned in_len,
                  unsigned char *out, unsigned out_cap);

/* What the last successful translation carried, for the log. */
typedef struct nav_translate_info {
    unsigned from_id, to_id;
    unsigned event, side, meters, seconds, road_len;
    int status;
} nav_translate_info;
NAV_TRANSLATE_HIDDEN const nav_translate_info *nav_translate_last(void);

#endif
