#include <pthread.h>
#include <unistd.h>
#include <stdexcept>
#include <cstdio>
static int depth(int n) { if (n == 0) throw std::runtime_error("deep"); return depth(n - 1) + 1; }
static void cl(void *) { printf("cleanup ran\n"); }
static void *th(void *) { pthread_cleanup_push(cl, 0); for (;;) { sleep(1); } pthread_cleanup_pop(0); return 0; }
int main() {
  int caught = 0; for (int i = 0; i < 1000; i++) try { depth(60); } catch (std::exception &e) { caught++; }
  printf("caught=%d\n", caught);
  pthread_t t; pthread_create(&t, 0, th, 0); usleep(200000); pthread_cancel(t); void *r; pthread_join(t, &r);
  printf("cancelled=%d\n", r == PTHREAD_CANCELED); return 0;
}
