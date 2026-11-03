#!/bin/sh
# Installs the sde-runtime wrapper, the SDE bundle and the k0s containerd handler `sde`.
#   install/install.sh [--binary PATH] [--bundle DIR] [--no-k0s]
#   install/install.sh --uninstall
# Does not restart anything; restart k0s (or containerd) afterwards to load the handler.
set -eu

BIN=/usr/local/bin/sde-runtime
BUNDLE_DEST=/opt/sde-bundle
CONF_DIR=/etc/sde-runtime
DROPIN=/etc/k0s/containerd.d/50-sde-runtime.toml

here=$(cd "$(dirname "$0")" && pwd)
binary=$here/../sde-runtime
bundle=$here/../bundle/out/sde
k0s=1
uninstall=0

while [ $# -gt 0 ]; do
    case $1 in
        --binary) binary=$2; shift 2 ;;
        --bundle) bundle=$2; shift 2 ;;
        --no-k0s) k0s=0; shift ;;
        --uninstall) uninstall=1; shift ;;
        *) echo "usage: $0 [--binary PATH] [--bundle DIR] [--no-k0s] | --uninstall" >&2; exit 2 ;;
    esac
done

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

if [ "$uninstall" = 1 ]; then
    rm -f "$DROPIN" "$BIN"
    rm -rf "$BUNDLE_DEST"
    # Keep the config in case it was edited; remove it only if it is the shipped example.
    rmdir "$CONF_DIR" 2>/dev/null || true
    echo "removed; restart k0s/containerd to drop the handler. Pods using the RuntimeClass fail until it is deleted."
    exit 0
fi

[ -x "$binary" ] || { echo "no binary at $binary (go build -o sde-runtime ./cmd/sde-runtime)" >&2; exit 1; }
[ -x "$bundle/sde64" ] || { echo "no SDE bundle at $bundle (run bundle/build.sh)" >&2; exit 1; }

install -m 0755 "$binary" "$BIN.new"
mv "$BIN.new" "$BIN"
rm -rf "$BUNDLE_DEST.new"
cp -a "$bundle" "$BUNDLE_DEST.new"
rm -rf "$BUNDLE_DEST"
mv "$BUNDLE_DEST.new" "$BUNDLE_DEST"

mkdir -p "$CONF_DIR"
if [ ! -e "$CONF_DIR/config.toml" ]; then
    cat > "$CONF_DIR/config.toml" <<'CONF'
# All keys are optional; defaults shown.
# real_runtime = "/var/lib/k0s/bin/runc"
# bundle_path  = "/opt/sde-bundle"
# chip         = "hsw"
# extra_args   = []
# log_file     = "/var/log/sde-runtime.log"
CONF
fi

if [ "$k0s" = 1 ]; then
    mkdir -p "$(dirname "$DROPIN")"
    cat > "$DROPIN" <<'TOML'
version = 2
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sde]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sde.options]
    BinaryName = "/usr/local/bin/sde-runtime"
TOML
fi
echo "installed; restart k0s/containerd to load the handler."
