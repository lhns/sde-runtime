#include <unistd.h>
#include <sys/wait.h>
#include "common.h"
int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) { fflush(stdout); pid_t p = fork(); if (!p) { execv(argv[i], (char *[]){argv[i], "forked", 0}); _exit(127); } int st; waitpid(p, &st, 0); printf("waited %d\n", WEXITSTATUS(st)); }
  printf("DRINFO maps_dr=%d\n", dr_maps()); return 0;
}
