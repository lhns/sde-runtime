// Exits 0 only if AVX2, FMA and BMI2 instructions return correct results.
#include <immintrin.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    volatile int a = 3, b = 4;
    __m256i v = _mm256_add_epi32(_mm256_set1_epi32(a), _mm256_set1_epi32(b));
    int avx2 = _mm256_extract_epi32(v, 7);

    volatile double x = 2.0, y = 3.0, z = 4.0;
    __m256d d = _mm256_fmadd_pd(_mm256_set1_pd(x), _mm256_set1_pd(y), _mm256_set1_pd(z));
    double fma = _mm256_cvtsd_f64(d);

    volatile uint64_t src = 0xff, mask = 0xf0f0;
    uint64_t bmi2 = _pdep_u64(src, mask);

    int ok = avx2 == 7 && fma == 10.0 && bmi2 == 0xf0f0;
    printf("avx2=%d fma=%g bmi2=%#llx %s\n", avx2, fma, (unsigned long long)bmi2, ok ? "ok" : "WRONG");
    return ok ? 0 : 1;
}
