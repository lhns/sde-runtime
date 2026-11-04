package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoad(t *testing.T) {
	dir := t.TempDir()
	c, err := Load(filepath.Join(dir, "missing.toml"))
	if err != nil || c.RealRuntime != "/var/lib/k0s/bin/runc" || c.Chip != "hsw" {
		t.Fatal(c, err)
	}
	p := filepath.Join(dir, "c.toml")
	os.WriteFile(p, []byte("chip = \"adl\"\nextra_args = [\"-x\"]\n"), 0o644)
	c, err = Load(p)
	if err != nil || c.Chip != "adl" || c.BundlePath != "/opt/sde-bundle" || len(c.ExtraArgs) != 1 {
		t.Fatal(c, err)
	}
	os.WriteFile(p, []byte("chip = "), 0o644)
	if _, err = Load(p); err == nil {
		t.Fatal("want error")
	}
}
