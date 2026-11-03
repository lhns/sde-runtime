#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <time.h>
#include <ucontext.h>
static void h(int s, siginfo_t *si, void *u) { ((ucontext_t *)u)->uc_mcontext.gregs[REG_RIP] += 2; }
int main(void) {
  struct sigaction sa = {0}; sa.sa_sigaction = h; sa.sa_flags = SA_SIGINFO; sigaction(SIGILL, &sa, 0);
  enum { N = 200000 }; struct timespec a, b; double best = 1e18;
  for (int r = 0; r < 5; r++) {
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 0; i < N; i++) __asm__ volatile("ud2");
    clock_gettime(CLOCK_MONOTONIC, &b);
    double ns = ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / N; if (ns < best) best = ns;
  }
  printf("ud2 SIGILL round trip: %.0f ns/iter (best of 5 x %d)\n", best, N); return 0;
}
