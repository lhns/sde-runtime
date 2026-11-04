#include <unistd.h>
#include "common.h"
int main(int argc, char **argv) { printf("DRINFO maps_dr=%d\n", dr_maps()); fflush(stdout); execv(argv[1], (char *[]){argv[1], "execed", 0}); perror("execv"); return 127; }
