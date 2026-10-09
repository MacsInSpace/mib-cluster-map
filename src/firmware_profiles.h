/*
 * Firmware profiles.
 *
 * Everything in the hook that depends on one particular build of the stock
 * Android Auto program (gal) is collected here. To support another firmware,
 * add one entry to k_profiles[] below; nothing else in the hook needs to know.
 *
 * How a profile is chosen
 *   The first three fields are the run-time addresses of three symbols that
 *   gal exports. They differ between builds, so together they identify the
 *   build. The hook resolves the symbols with dlsym and picks the entry whose
 *   three addresses all match. No match: the hook logs a fingerprint line with
 *   the three addresses it found and leaves Android Auto stock.
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
 * be described without touching code. docs: wiki/Porting-To-Another-Firmware.md
 *
 * A profile must not be added on the strength of the tool's output alone. Check
 * each field against the disassembly, then test on a car with that firmware.
 */
#ifndef FIRMWARE_PROFILES_H
#define FIRMWARE_PROFILES_H

#include <stdint.h>

typedef struct gal_profile {
    const char *name;            /* firmware train, for the log */
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

static const gal_profile k_profiles[] = {
    /*
     * VW Discover Pro 9.2", MIB2.5 High. gal sha256 f84722179cbf..., 1269211
     * bytes; libautoreceiver.so sha256 b04cb5cf3b8c..., 1067402 bytes.
     * Layouts verified in wiki/Receiver-Layout-Verification.md.
     */
    {
        "MHI2_ER_VWG13_P4521", 1,
        0x00237f70u, 0x00231e08u, 0x00231d18u,
        0x001d9658u, 0xe92d4ff0u, 0xf0u,
        0x94u, 0xc4u,
        0x80u, 0x84u, 40u,
        0x34u, 0x58u, 59u
    },
};

#define GAL_PROFILE_COUNT (sizeof(k_profiles) / sizeof(k_profiles[0]))
#define GAL_PROFILE_MAX_ENTRY 64u

#endif
