// N threads spin in one shared tight loop; a monitor signals each once per round and
// waits for every handler. Exit 3 = a thread never got its signal (hang).
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define MAXT 64
static volatile int stop;
static atomic_int ready, flag[MAXT];
static _Thread_local int idx;
static pid_t tids[MAXT];

static void handler(int s) { (void)s; atomic_store(&flag[idx], 1); }

__attribute__((noinline)) static void spin(void) {
    __asm__ volatile("1: cmpl $0, %0\n\tje 1b\n" : : "m"(stop) : "cc");
}
static void *worker(void *a) {
    idx = (int)(long)a;
    tids[idx] = (pid_t)syscall(SYS_gettid);
    atomic_fetch_add(&ready, 1);
    spin();
    return NULL;
}
static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 8, rounds = argc > 2 ? atoi(argv[2]) : 200;
    double tmo = argc > 3 ? atof(argv[3]) : 5;
    pthread_t th[MAXT];
    struct sigaction sa = { .sa_handler = handler };
    sigaction(SIGUSR1, &sa, NULL);
    for (long i = 0; i < n; i++) pthread_create(&th[i], NULL, worker, (void *)i);
    while (atomic_load(&ready) < n) usleep(100);
    usleep(50000); /* let the loop reach its final fragment */
    for (int r = 0; r < rounds; r++) {
        for (int i = 0; i < n; i++) atomic_store(&flag[i], 0);
        for (int i = 0; i < n; i++) pthread_kill(th[i], SIGUSR1);
        double t0 = now();
        for (;;) {
            int done = 0;
            for (int i = 0; i < n; i++) done += atomic_load(&flag[i]);
            if (done == n) break;
            if (now() - t0 > tmo) {
                printf("HANG round %d:", r);
                for (int i = 0; i < n; i++)
                    if (!atomic_load(&flag[i])) printf(" tid=%d", tids[i]);
                printf("\n");
                fflush(stdout);
                _exit(3);
            }
            usleep(50);
        }
    }
    stop = 1;
    for (int i = 0; i < n; i++) pthread_join(th[i], NULL);
    printf("ok\n");
    return 0;
}
