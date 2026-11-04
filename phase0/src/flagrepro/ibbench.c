// Worst case for always restoring flags: a hot indirect call to a block that writes them first.
#include <stdio.h>
static volatile long x;
static __attribute__((noinline)) void f(void) { x += 1; }
int main(void) {
    void (*volatile p)(void) = f;
    for (long i = 0; i < 300000000; i++)
        p();
    printf("%ld\n", x);
    return 0;
}
