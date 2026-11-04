#include <sys/mman.h>
#include <string.h>
#include "common.h"
int main(void) {
  unsigned char *p = mmap(0, 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  long sum = 0; int (*f)(void) = (int (*)(void))p;
  for (int i = 0; i < 20000; i++) { unsigned char c[] = {0xb8, (unsigned char)(i & 0xff), (unsigned char)(i >> 8), 0, 0, 0xc3}; memcpy(p, c, sizeof c); sum += f(); }
  mprotect(p, 4096, PROT_READ | PROT_WRITE);
  for (int i = 0; i < 2000; i++) { p[1] = (unsigned char)(i * 3); mprotect(p, 4096, PROT_READ | PROT_EXEC); sum += f(); mprotect(p, 4096, PROT_READ | PROT_WRITE); }
  p[1] = 0x00; /* patch one byte inside a running loop's own page */
  printf("smc sum=%ld\n", sum); printf("DRINFO maps_dr=%d\n", dr_maps()); return 0;
}
