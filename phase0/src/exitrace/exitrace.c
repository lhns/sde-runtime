// Creator threads clone continually, up to CAP live threads, while main calls exit: a clone
// races process exit. No signals are sent, so a DR hang here is not the delayed-signal bug.
// exitrace [CAP]: CAP 0 is uncapped, which takes down a CI runner under DR.
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static atomic_long live, created;
static long cap = 256;

static void *leaf(void *a) {
    atomic_fetch_sub(&live, 1);
    return a;
}
static void *creator(void *a) {
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    for (;;) {
        pthread_t t;
        if (cap && atomic_load(&live) >= cap) {
            sched_yield();
            continue;
        }
        atomic_fetch_add(&live, 1);
        if (pthread_create(&t, &at, leaf, a) != 0)
            atomic_fetch_sub(&live, 1);
        else
            atomic_fetch_add(&created, 1);
    }
}
int main(int argc, char **argv) {
    if (argc > 1)
        cap = atol(argv[1]);
    for (int i = 0; i < 4; i++) {
        pthread_t t;
        pthread_create(&t, NULL, creator, NULL);
    }
    usleep(30000);
    printf("ok created=%ld\n", atomic_load(&created));
    fflush(stdout);
    exit(0);
}
