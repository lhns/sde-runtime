#include <immintrin.h>
#include <cpuid.h>
#include "common.h"
int main(void) {
  unsigned a, b, c, d; __cpuid_count(7, 0, a, b, c, d);
  __m256i s = _mm256_setzero_si256();
  for (int i = 0; i < 1000; i++) s = _mm256_add_epi32(s, _mm256_set1_epi32(i));
  int o[8]; _mm256_storeu_si256((__m256i *)o, s);
  printf("avx2cpu=%d sum=%d\n", !!(b >> 5 & 1), o[0] + o[7]);
  printf("DRINFO maps_dr=%d\n", dr_maps());
  return 0;
}
