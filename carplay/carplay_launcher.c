/*
 * Linked into libcarplay_cluster.so with harman-f's cluster-stream hook
 * (thirdparty/mhi2_altscreen_carplay), which is preloaded into dio_manager,
 * the CarPlay program. This part only starts carplay_cluster.sh, the
 * supervisor that runs stream-player while CarPlay's cluster video is live.
 * dio_manager starts when an iPhone connects, so the supervisor needs no boot
 * hook of its own.
 *
 * Processes dio_manager spawns inherit LD_PRELOAD and with it this library;
 * CLUSTERMAP_CARPLAY_OWNER, set here before anything is spawned, makes
 * those skip it (the same guard as the Android Auto hook's
 * GAL_HOOK_OWNER_PID).
 */
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#ifdef __QNX__
#include <spawn.h>
#endif

#define SUPERVISOR "/mnt/app/eso/lib/gal_dualscreen/carplay_cluster.sh"
#define LAUNCH_LOG "/tmp/carplay_cluster.log"

static pid_t g_child = -1;

/* Reap the supervisor when it ends, so it does not linger as a zombie of
 * dio_manager. */
static void *reaper(void *arg)
{
    (void)arg;
    while (waitpid(g_child, NULL, 0) < 0 && errno == EINTR) {}
    return NULL;
}

__attribute__((constructor))
static void carplay_launcher_start(void)
{
    char owner[24];
    char size[24];
    const char *w = getenv("ALTSCREEN111_WIDTH");
    const char *h = getenv("ALTSCREEN111_HEIGHT");
    char *argv[5];
    char *envp[] = {
        (char *)"PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/eso/bin:/mnt/app/eso/bin:/mnt/app/navigation",
        (char *)"LD_LIBRARY_PATH=/proc/boot:/lib:/lib/dll:/usr/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib:/eso/lib:/mnt/app/eso/lib",
        (char *)"IPL_CONFIG_DIR=/etc/eso/production",
        NULL
    };
    pthread_t t;
    pthread_attr_t attr;
    int log_fd, null_fd;

    if (getenv("CLUSTERMAP_CARPLAY_OWNER") != NULL) return;
    (void)snprintf(owner, sizeof owner, "%ld", (long)getpid());
    (void)setenv("CLUSTERMAP_CARPLAY_OWNER", owner, 1);
    if (access(SUPERVISOR, R_OK) != 0) return;

    argv[0] = (char *)"ksh";
    argv[1] = (char *)SUPERVISOR;
    argv[2] = owner;
    /* The size the installer asked CarPlay for, so the player's window
     * matches the stream. */
    (void)snprintf(size, sizeof size, "%sx%s", w ? w : "800", h ? h : "480");
    argv[3] = size;
    argv[4] = NULL;

    null_fd = open("/dev/null", O_RDWR);
    log_fd = open(LAUNCH_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (log_fd < 0) log_fd = null_fd;
    if (null_fd < 0 || log_fd < 0) {
        if (null_fd >= 0) close(null_fd);
        return;
    }
#ifdef __QNX__
    {
        /* Explicit environment and descriptors: none of dio_manager's
         * sockets, and no LD_PRELOAD, reach the supervisor. */
        struct inheritance inherit;
        int map[3];
        map[0] = null_fd;
        map[1] = log_fd;
        map[2] = log_fd;
        memset(&inherit, 0, sizeof inherit);
        inherit.flags = SPAWN_SETSIGMASK | SPAWN_SETGROUP;
        inherit.pgroup = SPAWN_NEWPGROUP;
        sigemptyset(&inherit.sigmask);
        g_child = spawn("/bin/ksh", 3, map, &inherit, argv, envp);
    }
#else
    g_child = fork();
    if (g_child == 0) {
        (void)dup2(null_fd, 0);
        (void)dup2(log_fd, 1);
        (void)dup2(log_fd, 2);
        (void)setpgid(0, 0);
        execve("/bin/ksh", argv, envp);
        _exit(127);
    }
#endif
    if (log_fd != null_fd) close(log_fd);
    close(null_fd);
    if (g_child <= 0) return;

    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &attr, reaper, NULL) != 0) {
        /* No reaper: still fine, the supervisor only becomes a zombie
         * after it has finished. */
    }
    pthread_attr_destroy(&attr);
}
