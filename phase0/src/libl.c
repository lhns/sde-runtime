#include <immintrin.h>
int f(unsigned x) { return (int)(_lzcnt_u32(x) + _pdep_u32(x, 0xF0F0F0F0u) + _tzcnt_u32(x | 1)); }
