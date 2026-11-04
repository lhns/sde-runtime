// Package wrapper decides what to do with one runtime invocation. It never fails: on any
// problem it logs and leaves the invocation unchanged, so the real runtime sees the original.
package wrapper

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/lhns/sde-runtime/internal/argv"
	"github.com/lhns/sde-runtime/internal/config"
	"github.com/lhns/sde-runtime/internal/spec"
)

type Deps struct {
	ConfigPath string
	// HostV3 reports whether the CPU has x86-64-v3 and the container can run natively.
	HostV3 func() bool
	// Logf must write neither to stdout nor stderr.
	Logf func(logFile, format string, a ...any)
	// State returns the bundle directory of a container (runtime `state`).
	State func(real string, global []string, id string) (string, error)
	Getwd func() (string, error)
}

// Defaults fills unset dependencies with the real ones (Logf and HostV3 stay caller's job).
func (d Deps) withDefaults() Deps {
	if d.State == nil {
		d.State = runtimeState
	}
	if d.Getwd == nil {
		d.Getwd = os.Getwd
	}
	if d.Logf == nil {
		d.Logf = func(string, string, ...any) {}
	}
	if d.HostV3 == nil {
		d.HostV3 = func() bool { return false }
	}
	return d
}

func runtimeState(real string, global []string, id string) (string, error) {
	out, err := exec.Command(real, append(append([]string{}, global...), "state", id)...).Output()
	if err != nil {
		return "", err
	}
	var s struct {
		Bundle string `json:"bundle"`
	}
	if err := json.Unmarshal(out, &s); err != nil {
		return "", err
	}
	return s.Bundle, nil
}

// Prepare applies the SDE rewrite to the files the invocation refers to, if it needs one, and
// returns the path of the real runtime to exec with args unchanged.
func Prepare(args []string, d Deps) string {
	d = d.withDefaults()
	cfg, err := config.Load(d.ConfigPath)
	if err != nil {
		d.Logf(config.Defaults().LogFile, "error: %v: passing through, nothing wrapped", err)
		return cfg.RealRuntime
	}
	logf := func(format string, a ...any) { d.Logf(cfg.LogFile, format, a...) }
	cmd := argv.Parse(args)
	switch cmd.Sub {
	case "create", "run":
		create(cmd, cfg, d, logf)
	case "exec":
		execCmd(cmd, cfg, d, logf)
	}
	return cfg.RealRuntime
}

func options(cfg config.Config) spec.Options {
	return spec.Options{BundlePath: cfg.BundlePath, Chip: cfg.Chip, ExtraArgs: cfg.ExtraArgs, InitPaths: cfg.InitPaths}
}

func create(cmd argv.Cmd, cfg config.Config, d Deps, logf func(string, ...any)) {
	id := cmd.ID()
	if !cfg.ForceOnCapableHost && d.HostV3() {
		logf("info: %s: host has x86-64-v3, running natively", id)
		return
	}
	bundle := cmd.Bundle
	if bundle == "" {
		var err error
		if bundle, err = d.Getwd(); err != nil {
			logf("error: %s: no bundle: %v: passing through", id, err)
			return
		}
	}
	cfgPath := filepath.Join(bundle, "config.json")
	if sb, err := spec.IsSandbox(cfgPath); err != nil {
		logf("error: %s: %v: passing through", id, err)
		return
	} else if sb {
		return // pod sandbox (pause) is baseline x86-64
	}
	if _, err := os.Stat(filepath.Join(cfg.BundlePath, "sde64")); err != nil {
		logf("error: %s: SDE bundle missing at %s: %v: passing through, the container will probably fail", id, cfg.BundlePath, err)
		return
	}
	changed, err := spec.RewriteConfig(cfgPath, options(cfg))
	switch {
	case err != nil:
		logf("error: %s: %v: passing through", id, err)
	case changed:
		logf("info: %s: wrapped in SDE (-%s), bundle %s", id, cfg.Chip, bundle)
	}
}

func execCmd(cmd argv.Cmd, cfg config.Config, d Deps, logf func(string, ...any)) {
	id := cmd.ID()
	if id == "" {
		return
	}
	if !cfg.ForceOnCapableHost && d.HostV3() {
		return // nothing was wrapped on this host
	}
	// A wrapped container has the marker; asking the runtime for the bundle is the only way
	// to read it, so exec in an unwrapped container costs one `state` call.
	bundle, err := d.State(cfg.RealRuntime, cmd.Global, id)
	if err != nil {
		logf("error: exec %s: cannot find bundle: %v: passing through", id, err)
		return
	}
	wrapped, err := spec.IsWrapped(filepath.Join(bundle, "config.json"))
	if err != nil {
		logf("error: exec %s: %v: passing through", id, err)
		return
	}
	if !wrapped {
		return
	}
	if cmd.Process == "" {
		logf("warn: exec %s: no --process file (inline args): passing through unwrapped", id)
		return
	}
	changed, err := spec.RewriteProcess(cmd.Process, options(cfg))
	switch {
	case err != nil:
		logf("error: exec %s: %v: passing through", id, err)
	case changed:
		logf("info: exec %s: wrapped in SDE", id)
	}
}
