/*
 * profile_check: does this unit's Android Auto program match a known profile?
 *
 *   profile_check <gal file> <profiles.conf>
 *
 * The hook decides this at run time with dlsym, but by then the install is
 * done. This reads the same three addresses from gal's dynamic symbol table,
 * so the installer can decide from the binary rather than the train's name,
 * and a unit we do not know reports what it has in its install log.
 *
 * Prints key=value lines and always prints the fingerprint it could read.
 * Exit code: 0 a profile matches, 1 none does, 2 gal could not be read.
 * Built for the unit and for the host (tests/profile_check_test.sh).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "firmware_profiles.h"

#define PT_LOAD 1u
#define PT_DYNAMIC 2u
#define DT_NULL 0u
#define DT_HASH 4u
#define DT_STRTAB 5u
#define DT_SYMTAB 6u

static const char K_CONTROLLER[] = "_ZN3gal14CGALController10s_instanceE";
static const char K_IMPL[] = "_ZTVN3gal14CVideoSinkImplE";
static const char K_CBHANDLER[] = "_ZTVN3gal25CVideoSinkCallbackHandlerE";

static unsigned char *g_file;
static size_t g_size;

static uint32_t rd32(size_t off)
{
    const unsigned char *p = g_file + off;
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static unsigned rd16(size_t off)
{
    return (unsigned)g_file[off] | (unsigned)g_file[off + 1] << 8;
}

/* File offset of a virtual address, or 0 when no segment holds n bytes there. */
static size_t file_offset(uint32_t vaddr, uint32_t n)
{
    uint32_t phoff = rd32(28);
    unsigned phsize = rd16(42), phnum = rd16(44), i;

    for (i = 0; i < phnum; ++i) {
        size_t ph = (size_t)phoff + (size_t)i * phsize;
        uint32_t off, va, filesz;
        if (ph + 32u > g_size || rd32(ph) != PT_LOAD) continue;
        off = rd32(ph + 4);
        va = rd32(ph + 8);
        filesz = rd32(ph + 16);
        if (vaddr >= va && vaddr - va <= filesz && filesz - (vaddr - va) >= n) {
            size_t r = (size_t)off + (vaddr - va);
            if (r + n <= g_size) return r;
        }
    }
    return 0;
}

static int read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    long n;

    if (f == NULL) return -1;
    if (fseek(f, 0, SEEK_END) != 0 || (n = ftell(f)) < 52 || fseek(f, 0, SEEK_SET) != 0) {
        (void)fclose(f);
        return -1;
    }
    g_size = (size_t)n;
    g_file = (unsigned char *)malloc(g_size);
    if (g_file == NULL || fread(g_file, 1, g_size, f) != g_size) {
        (void)fclose(f);
        return -1;
    }
    (void)fclose(f);
    if (memcmp(g_file, "\177ELF\001\001", 6) != 0) return -1; /* ELF32 little endian */
    return 0;
}

/* The three symbols' addresses; 0 for any that is missing. -1: no symbol table. */
static int read_fingerprint(uint32_t out[3])
{
    uint32_t phoff = rd32(28), strtab = 0, symtab = 0, hash = 0;
    unsigned phsize = rd16(42), phnum = rd16(44), i;
    size_t dyn = 0, dynsize = 0, symoff, stroff, hashoff;
    uint32_t nsym;

    for (i = 0; i < phnum; ++i) {
        size_t ph = (size_t)phoff + (size_t)i * phsize;
        if (ph + 32u > g_size) return -1;
        if (rd32(ph) == PT_DYNAMIC) {
            dyn = rd32(ph + 4);
            dynsize = rd32(ph + 16);
        }
    }
    if (dyn == 0u || dyn + dynsize > g_size) return -1;
    for (i = 0; (size_t)i + 8u <= dynsize; i += 8u) {
        uint32_t tag = rd32(dyn + i), val = rd32(dyn + i + 4u);
        if (tag == DT_NULL) break;
        if (tag == DT_HASH) hash = val;
        else if (tag == DT_STRTAB) strtab = val;
        else if (tag == DT_SYMTAB) symtab = val;
    }
    hashoff = file_offset(hash, 8u);
    stroff = file_offset(strtab, 1u);
    symoff = file_offset(symtab, 16u);
    if (hashoff == 0u || stroff == 0u || symoff == 0u) return -1;
    nsym = rd32(hashoff + 4u); /* nchain equals the number of symbols */
    out[0] = out[1] = out[2] = 0u;
    for (i = 0; i < nsym; ++i) {
        size_t sym = symoff + (size_t)i * 16u;
        size_t name;
        const char *s;
        if (sym + 16u > g_size) return -1;
        name = stroff + rd32(sym);
        if (name >= g_size || rd16(sym + 14u) == 0u) continue; /* undefined here */
        if (memchr(g_file + name, 0, g_size - name) == NULL) continue;
        s = (const char *)g_file + name;
        if (strcmp(s, K_CONTROLLER) == 0) out[0] = rd32(sym + 4u);
        else if (strcmp(s, K_IMPL) == 0) out[1] = rd32(sym + 4u);
        else if (strcmp(s, K_CBHANDLER) == 0) out[2] = rd32(sym + 4u);
    }
    return 0;
}

int main(int argc, char **argv)
{
    static gal_profile table[GAL_PROFILE_MAX];
    uint32_t fp[3];
    unsigned count, rejected, i;

    if (argc != 3) {
        fprintf(stderr, "usage: profile_check <gal file> <profiles.conf>\n");
        return 2;
    }
    if (read_file(argv[1]) != 0 || read_fingerprint(fp) != 0) {
        printf("gal=unreadable path=%s\n", argv[1]);
        return 2;
    }
    printf("gal_bytes=%lu\n", (unsigned long)g_size);
    printf("fingerprint=%x:%x:%x\n", (unsigned)fp[0], (unsigned)fp[1], (unsigned)fp[2]);
    count = gal_hook_profile_load(argv[2], table, GAL_PROFILE_MAX, &rejected);
    printf("profiles=%u rejected=%u\n", count, rejected);
    for (i = 0; i < count; ++i) {
        const gal_profile *p = &table[i];
        size_t ctor;
        if (p->controller_slot != fp[0] || p->impl_vtable != fp[1] ||
            p->cbhandler_vtable != fp[2])
            continue;
        ctor = file_offset(p->ctor, 4u);
        if (ctor == 0u || rd32(ctor) != p->ctor_first_word) {
            printf("match=none near=%s reason=constructor_word\n", p->name);
            return 1;
        }
        printf("match=%s tested=%d\n", p->name, p->car_tested);
        return 0;
    }
    printf("match=none\n");
    return 1;
}
