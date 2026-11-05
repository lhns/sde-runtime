# v3compat-runtime

Runs container images that need x86-64-v3 (AVX2, BMI2, FMA) on older CPUs under
[Intel SDE](https://www.intel.com/content/www/us/en/developer/articles/tool/software-development-emulator.html),
through an OCI runtime wrapper for containerd + runc (Kubernetes).

**SDE is a slow fallback, not a fast path.** It is a binary translator: expect tens of seconds of startup and
compute 35-80 times slower than native (measured on DuckDB; your workload will differ). Every
process started in a wrapped container pays that startup, `kubectl exec` and exec probes included, so
use HTTP or TCP probes and a startup probe that allows for it. Use it to
let a pod run on an old node at all, not to run heavy pods there.

## How it works

Pods opt in with a RuntimeClass whose handler is `sde`. Other pods keep the default handler and never
see the wrapper. For each container created through that handler, `sde-runtime`:

1. passes through untouched if the CPU has x86-64-v3 (AVX, AVX2, BMI1, BMI2, FMA). The same pod runs
   natively on new nodes and under SDE only on old ones;
2. otherwise edits the bundle's `config.json`: bind-mounts the SDE bundle read-only at `/sde`, prefixes
   `process.args` with `/sde/sde64 -hsw --`, and sets the annotation `sde-runtime.wrapped=true`.
   An init process (`/sbin/docker-init`, `/run/podman-init`, `/dev/init`) stays native and runs SDE as
   its child. Pod sandbox (pause) containers are not wrapped;
3. `exec` into a wrapped container (`kubectl exec`, exec probes) gets the same prefix in its process file;
4. then `execve`s the real runtime with the original arguments. Every other subcommand does only that,
   without forking. SDE follows `exec` of child processes by default.

Any error (broken config, missing bundle, unparsable spec) is logged and the invocation passes through
unchanged. The wrapper never writes to stdout/stderr. Logs go to syslog (`sde-runtime`) and
`/var/log/sde-runtime.log`.

Not supported: images without a glibc, automatic detection of images that need v3 (opt in by RuntimeClass),
CPUs without AVX. Only the runc command line is tested; the argument handling is runtime-neutral.

## Build and install

SDE is Intel's software under its own license and is never part of this repo or its releases.

    docker run --rm -v "$PWD":/w -w /w debian:stable bundle/build.sh --accept-intel-license
    go build -o sde-runtime ./cmd/v3compat-runtime
    sudo install/install.sh          # binary, bundle, config, k0s handler drop-in
    sudo install/install.sh --uninstall

`bundle/build.sh` downloads the pinned SDE, checks its sha256 and asks you to accept Intel's license
(`--accept-intel-license` or `SDE_ACCEPT_LICENSE=1`). To use a tarball you downloaded yourself, pass
`--tarball PATH`. Do not publish the result. Files are not patched (`bundle/INVENTORY.md`).

Install the handler on every node that may run opted-in pods: a RuntimeClass whose handler is missing
fails the pod. On nodes with x86-64-v3 the wrapper just passes through.

## k0s / containerd

`install/install.sh` writes `/etc/k0s/containerd.d/50-sde-runtime.toml` (containerd config v2 syntax):

```toml
version = 2
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sde]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sde.options]
    BinaryName = "/usr/local/bin/sde-runtime"
```

With containerd 2 / config `version = 3` the plugin is `io.containerd.cri.v1.runtime` instead of
`io.containerd.grpc.v1.cri`. Restart k0s or containerd afterwards. Then:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sde
handler: sde
---
# in the pod spec
spec:
  runtimeClassName: sde
```

## Configuration

`/etc/sde-runtime/config.toml`, all keys optional (defaults shown). A missing file means defaults; an
invalid one means pass-through.

```toml
real_runtime = "/var/lib/k0s/bin/runc"   # the runtime to exec
bundle_path  = "/opt/sde-bundle"         # host path, mounted at /sde
chip         = "hsw"                     # sde64 -<chip>
extra_args   = []                        # more sde64 arguments
init_paths   = ["/sbin/docker-init", "/run/podman-init", "/dev/init"]
log_file     = "/var/log/sde-runtime.log"
force_on_capable_host = false            # testing: wrap even on x86-64-v3
```

## Development

    go test ./...
    GOOS=linux GOARCH=amd64 go build ./cmd/v3compat-runtime

`test/probe` exits 0 only if AVX2, FMA and BMI2 instructions return correct results. An end-to-end run
needs the SDE bundle (not available in CI) and a node without AVX2 (for example
`qemu -cpu IvyBridge`); it is not automated.

## License

The wrapper is licensed under [Apache-2.0](LICENSE). Intel SDE is not part of this repo and has its own license.
