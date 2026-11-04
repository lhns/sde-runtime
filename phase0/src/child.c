#include <unistd.h>
#include "common.h"
int main(int argc, char **argv) { printf("child %s ok\n", argc > 1 ? argv[1] : "-"); printf("DRINFO maps_dr=%d\n", dr_maps()); return 0; }
