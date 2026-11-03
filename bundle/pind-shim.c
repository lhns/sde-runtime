// Runs Intel's unmodified pind through the bundled loader, for images without a usable glibc.
// Pass to pin as -pind_path_64.
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    char *args[argc + 4];
    int n = 0;
    args[n++] = "/sde/lib/ld-linux-x86-64.so.2";
    args[n++] = "--library-path";
    args[n++] = "/sde/lib:/sde/intel64/pin_lib";
    args[n++] = "/sde/intel64/pinrt/pind";
    for (int i = 1; i < argc; i++)
        args[n++] = argv[i];
    args[n] = NULL;
    execv(args[0], args);
    perror("execv");
    return 127;
}
