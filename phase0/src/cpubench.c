#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
static int cmp(const void *a, const void *b) { int x = *(const int *)a, y = *(const int *)b; return (x > y) - (x < y); }
int main(void) {
  uint64_t s = 88172645463325252ULL, acc = 0;
  for (long i = 0; i < 400000000L; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; acc += s & 0xff; }
  printf("xorshift %llu\n", (unsigned long long)acc);
  int N = 30000000; char *sv = calloc(N + 1, 1); long cnt = 0;
  for (long i = 2; i <= N; i++) if (!sv[i]) { cnt++; for (long j = i * i; j <= N; j += i) sv[j] = 1; }
  printf("primes %ld\n", cnt);
  int M = 4000000; int *a = malloc(M * sizeof(int)); for (int i = 0; i < M; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; a[i] = (int)(s >> 33); }
  qsort(a, M, sizeof(int), cmp); printf("sorted %d %d\n", a[0], a[M - 1]);
  double x = 0; for (long i = 1; i < 100000000L; i++) x += 1.0 / ((double)i * i);
  printf("zeta %.9f\n", x);
  return 0;
}
