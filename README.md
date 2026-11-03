# sde-runtime

Runs container images that need x86-64-v3 (AVX2, BMI2, FMA) on older CPUs under
[Intel SDE](https://www.intel.com/content/www/us/en/developer/articles/tool/software-development-emulator.html).
Early stage: this repo holds the bundle script and a probe; the OCI runtime wrapper is not written yet.

This repo contains no SDE files. `bundle/build.sh` downloads the pinned version from Intel,
checks its sha256 and asks you to accept Intel's license first. To use a copy you downloaded
yourself, pass `--tarball PATH`.

    docker run --rm -v "$PWD":/w -w /w debian:stable bundle/build.sh --accept-intel-license

Do not publish the result, in a registry or anywhere else.

`bundle/INVENTORY.md` classifies the ELF files in the kit. `test/probe` exits 0 only if AVX2, FMA
and BMI2 instructions return correct results.
