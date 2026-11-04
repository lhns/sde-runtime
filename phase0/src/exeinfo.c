#include <unistd.h>
#include <sys/auxv.h>
#include "common.h"
int main(int argc, char **argv) { char b[512]; ssize_t n = readlink("/proc/self/exe", b, sizeof b - 1); b[n > 0 ? n : 0] = 0;
  printf("exe=%s\nargv0=%s\nexecfn=%s\n", b, argv[0], (char *)getauxval(AT_EXECFN)); printf("DRINFO maps_dr=%d\n", dr_maps()); return 0; }
