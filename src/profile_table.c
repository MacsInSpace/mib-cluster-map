/*
 * The firmware profile table, read from profiles.conf (see firmware_profiles.h).
 *
 * Reading the table is the one piece of this hook that cannot be allowed to do
 * anything clever: it runs inside gal before anything is known about the unit.
 * So no allocation, a fixed table, and any line that does not parse is skipped
 * and counted rather than acted on.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "firmware_profiles.h"

int gal_hook_profile_parse(const char *line, gal_profile *out)
{
    char name[GAL_PROFILE_NAME_MAX];
    unsigned f[14];
    unsigned stock;
    int tested;

    if (strncmp(line, "profile", 7) != 0 || (line[7] != ' ' && line[7] != '\t')) return 0;
    if (sscanf(line + 7, " %47s %d %x %x %x %x %x %x %x %x %x %x %x %x %x %u",
               name, &tested, &f[0], &f[1], &f[2], &f[3], &f[4], &f[5], &f[6],
               &f[7], &f[8], &f[9], &f[10], &f[11], &f[12], &stock) != 16)
        return -1;
    memset(out, 0, sizeof *out);
    (void)snprintf(out->name, sizeof out->name, "%s", name);
    out->car_tested = tested != 0;
    out->controller_slot = f[0];
    out->impl_vtable = f[1];
    out->cbhandler_vtable = f[2];
    out->ctor = f[3];
    out->ctor_first_word = f[4];
    out->handler_size = f[5];
    out->ctl_config_off = f[6];
    out->ctl_creator_off = f[7];
    out->h_cfg_count_off = f[8];
    out->h_cfg_data_off = f[9];
    out->cfg_entry_size = f[10];
    out->settings_first = f[11];
    out->settings_last = f[12];
    out->stock_displayable = stock;
    return 1;
}

unsigned gal_hook_profile_load(const char *path, gal_profile *table, unsigned max,
                               unsigned *rejected)
{
    char line[256];
    unsigned count = 0u;
    FILE *f;

    if (rejected != NULL) *rejected = 0u;
    f = fopen(path, "r");
    if (f == NULL) return 0u;
    while (fgets(line, sizeof line, f) != NULL) {
        gal_profile p;
        int r = gal_hook_profile_parse(line, &p);
        if (r < 0 && rejected != NULL) ++*rejected;
        if (r <= 0) continue;
        if (count == max) {
            if (rejected != NULL) ++*rejected;
            continue;
        }
        table[count++] = p;
    }
    (void)fclose(f);
    return count;
}
