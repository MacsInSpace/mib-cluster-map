/* mib-cluster-map QNX iPod-driver iAP2 route-guidance proxy.
 * Delegates the driver interface to the preserved stock module
 * (/mnt/app/armle/lib/dll/ipod-drvr-iap2.stock.so) and attaches the
 * passive iAP2 route-guidance capability & observer (rgd_adapter.c).
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <errno.h>

#ifndef RGD_STOCK_DRIVER
#define RGD_STOCK_DRIVER "/mnt/app/armle/lib/dll/ipod-drvr-iap2.stock.so"
#endif
#ifndef RGD_PROBE_LOG
#define RGD_PROBE_LOG "/tmp/clustermap-rgd.log"
#endif

#if UINTPTR_MAX == UINT32_MAX
typedef char module_pointer_size_must_be_four[(sizeof(void *) == 4) ? 1 : -1];
#elif !defined(RGD_HOST_TEST)
#error This proxy is specific to QNX ARM32.
#endif

const char clustermap_rgd_proxy_marker[] = "CLUSTERMAP_RGD_PROXY";
uintptr_t ipod_module[9];
static void *stock_handle;

#ifdef RGD_ADAPTER
extern void rgd_install(void *, uintptr_t *);
#endif

static void note(const char *s) {
    int saved = errno, fd = open(RGD_PROBE_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, s, strlen(s));
        write(fd, "\n", 1);
        close(fd);
    }
    errno = saved;
}

__attribute__((constructor)) static void load_stock(void) {
    uintptr_t *module, *driver;
    uint16_t version;
    note(clustermap_rgd_proxy_marker);
    stock_handle = dlopen(RGD_STOCK_DRIVER, RTLD_GLOBAL);
    if (!stock_handle) {
        const char *error = dlerror();
        note("probe failed: cannot load preserved stock driver");
        if (error) note(error);
        _exit(78);
    }
    module = (uintptr_t *)dlsym(stock_handle, "ipod_module");
    if (!module || module == ipod_module) {
        note("probe failed: stock module missing or loader alias");
        _exit(78);
    }
    memcpy(&version, &module[1], sizeof(version));
    if ((version >> 8) != 2 || !module[8]) {
        note("probe failed: unexpected driver ABI");
        _exit(78);
    }
    driver = (uintptr_t *)module[8];
    if (!driver[0] || strcmp((const char *)driver[0], "ipod_drvr")) {
        note("probe failed: unexpected interface name");
        _exit(78);
    }
    memcpy(ipod_module, module, sizeof(ipod_module));
    if (dlsym(stock_handle, "ident_info_funcs") && dlsym(stock_handle, "iap2_ctrl_msg_table"))
        note("PASS: stock interface delegated; identification/control tables found");
    else
        note("PASS: stock interface delegated; capability tables unavailable");
#ifdef RGD_ADAPTER
    rgd_install(stock_handle, driver);
#endif
}

