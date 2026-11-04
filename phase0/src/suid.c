#include <unistd.h>
#include "common.h"
int main(void) { printf("uid=%d euid=%d\n", getuid(), geteuid()); printf("DRINFO maps_dr=%d\n", dr_maps()); return 0; }
