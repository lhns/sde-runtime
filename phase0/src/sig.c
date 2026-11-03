#define _GNU_SOURCE
#include <signal.h>
#include <setjmp.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include "common.h"
static sigjmp_buf jb; static volatile int hits;
static void h(int s) { hits++; siglongjmp(jb, 1); }
static int rec(int n) { volatile char pad[512]; pad[0] = n; return rec(n + 1) + pad[0]; }
int main(int argc, char **argv) {
  const char *m = argc > 1 ? argv[1] : "segv";
  if (!strcmp(m, "term")) { printf("raising\n"); fflush(stdout); raise(SIGTERM); printf("not reached\n"); return 0; }
  struct sigaction sa = {0}; sa.sa_handler = h; sa.sa_flags = SA_NODEFER | SA_ONSTACK; sigemptyset(&sa.sa_mask);
  if (!strcmp(m, "altstack")) {
    stack_t ss = { .ss_sp = malloc(1 << 16), .ss_size = 1 << 16 }; sigaltstack(&ss, 0);
    sigaction(SIGSEGV, &sa, 0);
    for (int i = 0; i < 20; i++) if (!sigsetjmp(jb, 1)) rec(0);
    printf("altstack hits=%d\n", hits); return hits == 20 ? 0 : 1;
  }
  sa.sa_flags = SA_NODEFER; sigaction(SIGSEGV, &sa, 0);
  for (int i = 0; i < 2000; i++) if (!sigsetjmp(jb, 1)) *(volatile int *)0 = i;
  printf("segv hits=%d\n", hits); return hits == 2000 ? 0 : 1;
}
