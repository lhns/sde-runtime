#define _GNU_SOURCE
#include <sched.h>
#include <sys/rseq.h>
#include "common.h"
int main(void) {
  struct rseq *r = (struct rseq *)((char *)__builtin_thread_pointer() + __rseq_offset);
  printf("rseq_size=%d registered=%d cpu_ok=%d getcpu_ok=%d\n", __rseq_size > 0, __rseq_size > 0 && (int)r->cpu_id >= 0, __rseq_size > 0 && (int)r->cpu_id < 4096, sched_getcpu() >= 0);
  printf("DRINFO maps_dr=%d\n", dr_maps()); return 0;
}
