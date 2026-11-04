// Package config reads /etc/sde-runtime/config.toml. All keys are optional.
package config

import (
	"errors"
	"io/fs"

	"github.com/BurntSushi/toml"
)

const DefaultPath = "/etc/sde-runtime/config.toml"

type Config struct {
	RealRuntime        string   `toml:"real_runtime"`
	BundlePath         string   `toml:"bundle_path"`
	Chip               string   `toml:"chip"`
	ExtraArgs          []string `toml:"extra_args"`
	InitPaths          []string `toml:"init_paths"`
	LogFile            string   `toml:"log_file"`
	ForceOnCapableHost bool     `toml:"force_on_capable_host"` // testing: wrap even on an x86-64-v3 host
}

func Defaults() Config {
	return Config{
		RealRuntime: "/var/lib/k0s/bin/runc",
		BundlePath:  "/opt/sde-bundle",
		Chip:        "hsw",
		InitPaths:   []string{"/sbin/docker-init", "/run/podman-init", "/dev/init"},
		LogFile:     "/var/log/sde-runtime.log",
	}
}

// Load returns the defaults if the file is missing. If it is invalid, it returns the defaults
// and the error; callers should then not wrap anything.
func Load(path string) (Config, error) {
	c := Defaults()
	_, err := toml.DecodeFile(path, &c)
	if errors.Is(err, fs.ErrNotExist) {
		return Defaults(), nil
	}
	if err != nil {
		return Defaults(), err
	}
	return c, nil
}
