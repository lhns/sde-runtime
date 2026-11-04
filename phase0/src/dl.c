#include <dlfcn.h>
#include "common.h"
int main(void) { void *h = dlopen("./libl.so", RTLD_NOW); if (!h) { printf("dlopen fail %s\n", dlerror()); return 1; }
  int (*f)(unsigned) = dlsym(h, "f"); printf("f=%d\n", f(0x1234)); printf("DRINFO maps_dr=%d\n", dr_maps()); return 0; }
