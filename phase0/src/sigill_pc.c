#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
extern char bad_insn[], bad_end[];
void bad(void);
__asm__(".text\n.globl bad\nbad:\n.globl bad_insn\nbad_insn: vpaddd %ymm0,%ymm1,%ymm2\n.globl bad_end\nbad_end: ret\n");
static void h(int s, siginfo_t *si, void *u) {
  ucontext_t *uc = u;
  printf("SIGILL code=%d si_addr=%p rip=%p expected=%p rip_match=%d si_addr_match=%d\n", si->si_code, si->si_addr,
         (void *)uc->uc_mcontext.gregs[REG_RIP], (void *)bad_insn, (char *)uc->uc_mcontext.gregs[REG_RIP] == bad_insn, (char *)si->si_addr == bad_insn);
  uc->uc_mcontext.gregs[REG_RIP] = (long)bad_end;
}
int main(void) {
  struct sigaction sa = {0}; sa.sa_sigaction = h; sa.sa_flags = SA_SIGINFO; sigaction(SIGILL, &sa, 0);
  bad(); printf("returned normally\n"); return 0;
}
