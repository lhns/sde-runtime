#include <cpuid.h>
#include <stdio.h>
int main(void) {
  unsigned a, b, c, d, b7 = 0, c81 = 0;
  __cpuid(1, a, b, c, d);
  unsigned c1 = c;
  if (__get_cpuid_max(0, 0) >= 7) { __cpuid_count(7, 0, a, b7, c, d); }
  __cpuid(0x80000001, a, b, c81, d);
  printf("avx=%d avx2=%d fma=%d f16c=%d movbe=%d bmi1=%d bmi2=%d lzcnt=%d\n", !!(c1 >> 28 & 1), !!(b7 >> 5 & 1),
         !!(c1 >> 12 & 1), !!(c1 >> 29 & 1), !!(c1 >> 22 & 1), !!(b7 >> 3 & 1), !!(b7 >> 8 & 1), !!(c81 >> 5 & 1));
  return 0;
}
