#!/bin/sh
# Builds bundle/out/sde (mounted as /sde in containers). Run on a baseline glibc, for example:
#   docker run --rm -v "$PWD":/w -w /w debian:stable bundle/build.sh --accept-intel-license
# Intel's files stay byte-identical: the SDE and Pin licenses forbid modification, so no patchelf.
set -eu

SDE_NAME=sde-external-10.13.1-2026-07-28-lin
SDE_URL=https://downloadmirror.intel.com/924984/$SDE_NAME.tar.xz
SDE_SHA256=94e97d623fec54385686e1e7ba65ebc9941748c05ee451423948334892bf2b50
LICENSE_URL=https://www.intel.com/content/www/us/en/developer/articles/license/end-user-license-agreement.html

out=$(dirname "$0")/out
tarball=
accept=${SDE_ACCEPT_LICENSE:-0}

while [ $# -gt 0 ]; do
    case $1 in
        --tarball) tarball=$2; shift 2 ;;
        --accept-intel-license) accept=1; shift ;;
        *) echo "usage: $0 [--tarball PATH] [--accept-intel-license]" >&2; exit 2 ;;
    esac
done

if [ "$accept" != 1 ]; then
    cat >&2 <<EOF
Intel SDE is licensed by Intel. Read its terms:
  $LICENSE_URL
Rerun with --accept-intel-license (or SDE_ACCEPT_LICENSE=1) if you accept them.
EOF
    exit 1
fi

if ! command -v xz >/dev/null || ! command -v curl >/dev/null || ! command -v gcc >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates curl gcc libc6-dev xz-utils
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -z "$tarball" ]; then
    tarball=$work/$SDE_NAME.tar.xz
    curl -fsSL -o "$tarball" "$SDE_URL"
fi
echo "$SDE_SHA256  $tarball" | sha256sum -c -

rm -rf "$out/sde"
mkdir -p "$out/sde/lib"
tar -xJf "$tarball" -C "$out/sde" --strip-components=1

# For images without a usable glibc: pind-shim runs pind through this baseline glibc.
libdir=/lib/x86_64-linux-gnu
for lib in ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1; do
    cp -L "$libdir/$lib" "$out/sde/lib/"
done
gcc -O2 -static -o "$out/sde/pind-shim" "$(dirname "$0")/pind-shim.c"
chmod -R a+rX "$out/sde"
echo "built $out/sde"
