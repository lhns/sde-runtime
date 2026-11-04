# ELF inventory: SDE 10.13.1 (2026-07-28), Linux kit

Metadata from `readelf -l -d`; `pinkit/` and 32-bit `ia32/` are not listed. No file is patched: the
SDE and Pin licenses forbid modification.

## Classes

- **Static launcher** (`pin`): no loader or libc needed; starts `pinbin` through `pin.ld.so`.
- **PinCRT** (`pinbin`, `pin_lib/*`, `xed_lib/*`, `sde-mix-mt.so`, `pinrt/pin.ld.so`): `pin` loads
  them with its own loader, so `pinbin`'s PT_INTERP is not used.
- **Needs the container's glibc through PT_INTERP** (`sde64`, `pinrt/pind`): fail in an image without
  `/lib64/ld-linux-x86-64.so.2`. Images without a glibc are not supported.
- **Not exec'd in the tested `-hsw --` path**: `xed64`, `sde_cntrl_client`, `nullapp`, `xed_ext_lib/*`.

## Files

| file | type | PT_INTERP | NEEDED | RUNPATH |
| --- | --- | --- | --- | --- |
| intel64/nullapp | EXEC | /lib64/ld-linux-x86-64.so.2 | libc.so.6 | - |
| intel64/pin_lib/libc++.so | DYN | - | libc++abi.so libunwind-dynamic.so libpincrt.so | - |
| intel64/pin_lib/libc++abi.so | DYN | - | libunwind-dynamic.so libpincrt.so | - |
| intel64/pin_lib/libdwarf.so | DYN | - | libpincrt.so | - |
| intel64/pin_lib/libpincrt.so | DYN | - | - | - |
| intel64/pin_lib/libpindwarf.so | DYN | - | libpincrt.so libc++abi.so libc++.so libunwind-dynamic.so libdwarf.so | - |
| intel64/pin_lib/libpinos.so | DYN | - | libm.so.6 libc.so.6 | - |
| intel64/pin_lib/libunwind-dynamic.so | DYN | - | libpincrt.so | - |
| intel64/pinbin | DYN | /lib64/ld-linux-x86-64.so.2 | libxed.so libc++.so libc++abi.so libunwind-dynamic.so libpincrt.so | - |
| intel64/pinrt/pind | EXEC | /lib64/ld-linux-x86-64.so.2 | libpinos.so libpthread.so.0 libdl.so.2 librt.so.1 libm.so.6 libc.so.6 ld-linux-x86-64.so.2 | - |
| intel64/pinrt/plugins/librsc-rpc-plugin.so | DYN | - | libpinos.so libm.so.6 libc.so.6 ld-linux-x86-64.so.2 | - |
| intel64/sde-mix-mt.so | DYN | - | libpincrt.so libc++.so libc++abi.so libunwind-dynamic.so libxed.so libpindwarf.so libdwarf.so | - |
| intel64/xed_ext_lib/libdwarf.so.3 | DYN | - | libc.so.6 | - |
| intel64/xed_ext_lib/libelf.so.1 | DYN | - | libc.so.6 | - |
| intel64/xed_lib/libxed.so | DYN | - | libpincrt.so | - |
| misc/sde_cntrl_client | EXEC | /lib64/ld-linux-x86-64.so.2 | libc.so.6 | - |
| pin | EXEC | - | - | - |
| sde64 | EXEC | /lib64/ld-linux-x86-64.so.2 | libc.so.6 | - |
| xed64 | EXEC | /lib64/ld-linux-x86-64.so.2 | libelf.so.1 libdwarf.so.3 libc.so.6 | $ORIGIN/intel64/xed_ext_lib:$ORIGIN/intel64/xed_lib:$ORIGIN/intel64/pin_lib:$ORIGIN/../extlib |
