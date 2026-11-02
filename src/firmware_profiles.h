/*
 * Firmware profiles.
 *
 * Everything in the hook that depends on one particular build of the stock
 * Android Auto program (gal) is data, in profiles.conf (config/profiles.conf
 * here, /eso/lib/gal_dualscreen/profiles.conf on the unit). To support another
 * firmware, add one line there; nothing else in the hook needs to know.
 *
 * How a profile is chosen
 *   The first three fields are the run-time addresses of three symbols that
 *   gal exports. They differ between builds, so together they identify the
 *   build. The hook resolves the symbols with dlsym and picks the entry whose
 *   three addresses all match. No match: the hook logs a fingerprint line with
 *   the three addresses it found and leaves Android Auto stock. tools/
 *   profile_check.c makes the same comparison from the gal file at install.
 *
 * The one value that cannot be looked up
 *   `ctor` is the address of gal's CVideoSinkCallbackHandler constructor. It is
 *   not exported, so it has to be found in the disassembly (tools/find_profile.py
 *   proposes it). Because calling a wrong address would crash gal, the hook
 *   also compares the first instruction word at that address with
 *   `ctor_first_word` before every use, and refuses on a mismatch.
 *
 * The remaining fields are object layouts inside gal. They were identical on
 * the builds seen so far, but they are per-profile so a build that differs can
 * be described without touching code. docs: docs/Development.md, "Adding a firmware"
 *
 * A profile must not be added on the strength of the tool's output alone. Check
 * each field against the disassembly, then test on a car with that firmware.
 */
#ifndef FIRMWARE_PROFILES_H
#define FIRMWARE_PROFILES_H

#include <stdint.h>

#define GAL_PROFILE_NAME_MAX 48
#define GAL_PROFILE_MAX 64u
#define GAL_PROFILE_MAX_ENTRY 64u

typedef struct gal_profile {
    char name[GAL_PROFILE_NAME_MAX]; /* firmware train, for the log */
    int car_tested;              /* 1 = has run on a car; 0 = derived only */

    /* --- build fingerprint: addresses of exported gal symbols ------------- */
    uint32_t controller_slot;    /* _ZN3gal14CGALController10s_instanceE */
    uint32_t impl_vtable;        /* _ZTVN3gal14CVideoSinkImplE */
    uint32_t cbhandler_vtable;   /* _ZTVN3gal25CVideoSinkCallbackHandlerE */

    /* --- the hidden constructor ------------------------------------------- */
    uint32_t ctor;               /* CVideoSinkCallbackHandler::CVideoSinkCallbackHandler */
    uint32_t ctor_first_word;    /* first instruction word at `ctor` */
    uint32_t handler_size;       /* operator new size at the stock call site */

    /* --- arguments the stock call site passes to the constructor ---------- */
    uint32_t ctl_config_off;     /* controller + this  -> second argument */
    uint32_t ctl_creator_off;    /* controller + this  -> fourth argument */

    /* --- the primary handler's video configuration table ------------------ */
    uint32_t h_cfg_count_off;    /* handler + this: number of entries */
    uint32_t h_cfg_data_off;     /* handler + this: pointer to the entries */
    uint32_t cfg_entry_size;     /* bytes per entry (at most 64) */

    /* --- renderer settings copied into the handler ------------------------ */
    uint32_t settings_first;     /* first and last word offsets scanned for the */
    uint32_t settings_last;      /* stock main-screen displayable id */
    uint32_t stock_displayable;  /* that id; 59 on VW */
} gal_profile;

/* 1: a profile line, written to *out. 0: not a profile line. -1: malformed. */
int gal_hook_profile_parse(const char *line, gal_profile *out);

/* Reads up to `max` profiles; *rejected counts lines that were left out. */
unsigned gal_hook_profile_load(const char *path, gal_profile *table, unsigned max,
                               unsigned *rejected);

#endif
