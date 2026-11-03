#include <stdio.h>
#include <string.h>
static int dr_maps(void) { FILE *f = fopen("/proc/self/maps", "r"); char l[1024]; int n = 0; if (!f) return -1; while (fgets(l, sizeof l, f)) if (strstr(l, "dynamorio")) n++; fclose(f); return n; }
