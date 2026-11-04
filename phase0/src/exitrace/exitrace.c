// Creator threads clone continually while main calls exit: a clone races process exit.
// No signals are sent, so a DR hang here is not the delayed-signal bug.
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void *leaf(void *a) { return a; }
static void *creator(void *a) {
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    for (;;) {
        pthread_t t;
        pthread_create(&t, &at, leaf, a);
    }
}
int main(void) {
    for (int i = 0; i < 4; i++) {
        pthread_t t;
        pthread_create(&t, NULL, creator, NULL);
    }
    usleep(30000);
    printf("ok\n");
    fflush(stdout);
    exit(0);
}
