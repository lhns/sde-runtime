// Package spec rewrites OCI config.json and exec process files. Documents are edited as generic
// JSON so fields this package does not know survive the round trip.
package spec

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	specs "github.com/opencontainers/runtime-spec/specs-go"
)

const (
	AnnotationWrapped = "sde-runtime.wrapped"
	SDEMount          = "/sde"
	SDEBinary         = "/sde/sde64"
)

type Options struct {
	BundlePath string   // host path of the SDE bundle, mounted at /sde
	Chip       string   // for example "hsw"
	ExtraArgs  []string // extra SDE arguments, before "--"
	InitPaths  []string // init binaries that stay native and run SDE as their child
}

func (o Options) prefix() []string {
	p := append([]string{SDEBinary, "-" + o.Chip}, o.ExtraArgs...)
	return append(p, "--")
}

// WrapArgs prefixes args with the SDE command. It reports false if args are already wrapped
// or empty.
func WrapArgs(args []string, o Options) ([]string, bool) {
	if len(args) == 0 {
		return args, false
	}
	at := 0
	for _, init := range o.InitPaths {
		if args[0] != init {
			continue
		}
		for i, a := range args {
			if a == "--" {
				at = i + 1
				break
			}
		}
		break
	}
	if at >= len(args) || args[at] == SDEBinary {
		return args, false
	}
	out := append([]string{}, args[:at]...)
	out = append(out, o.prefix()...)
	return append(out, args[at:]...), true
}

type doc map[string]any

func load(path string) (doc, os.FileMode, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nil, 0, err
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var d doc
	if err := dec.Decode(&d); err != nil {
		return nil, 0, fmt.Errorf("%s: %w", path, err)
	}
	if d == nil {
		return nil, 0, fmt.Errorf("%s: not a JSON object", path)
	}
	return d, st.Mode().Perm(), nil
}

// save writes atomically: temp file in the same directory, fsync, rename.
func save(path string, d doc, mode os.FileMode) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(d); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".sde-runtime-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(buf.Bytes()); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(mode); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func rewriteArgs(m map[string]any, o Options) (bool, error) {
	raw, ok := m["args"].([]any)
	if !ok || len(raw) == 0 {
		return false, nil
	}
	args := make([]string, len(raw))
	for i, e := range raw {
		s, ok := e.(string)
		if !ok {
			return false, fmt.Errorf("process.args has a non-string entry")
		}
		args[i] = s
	}
	wrapped, changed := WrapArgs(args, o)
	if changed {
		out := make([]any, len(wrapped))
		for i, s := range wrapped {
			out[i] = s
		}
		m["args"] = out
	}
	return changed, nil
}

func annotations(d doc) map[string]any {
	a, _ := d["annotations"].(map[string]any)
	return a
}

// IsSandbox reports whether config.json describes a Kubernetes pod sandbox (pause) container.
func IsSandbox(path string) (bool, error) {
	d, _, err := load(path)
	if err != nil {
		return false, err
	}
	a := annotations(d)
	for _, k := range []string{"io.kubernetes.cri.container-type", "io.kubernetes.cri-o.ContainerType"} {
		if a[k] == "sandbox" {
			return true, nil
		}
	}
	return false, nil
}

// IsWrapped reports whether config.json carries the marker set by RewriteConfig.
func IsWrapped(path string) (bool, error) {
	d, _, err := load(path)
	if err != nil {
		return false, err
	}
	return annotations(d)[AnnotationWrapped] == "true", nil
}

// RewriteConfig wraps the container of a bundle's config.json. It is idempotent.
func RewriteConfig(path string, o Options) (bool, error) {
	d, mode, err := load(path)
	if err != nil {
		return false, err
	}
	p, ok := d["process"].(map[string]any)
	if !ok {
		return false, fmt.Errorf("%s: no process", path)
	}
	changed, err := rewriteArgs(p, o)
	if err != nil || !changed {
		return false, err
	}
	mounts, _ := d["mounts"].([]any)
	have := false
	for _, e := range mounts {
		if m, _ := e.(map[string]any); m["destination"] == SDEMount {
			have = true
		}
	}
	if !have {
		b, _ := json.Marshal(specs.Mount{
			Destination: SDEMount, Type: "bind", Source: o.BundlePath,
			Options: []string{"rbind", "ro", "nosuid", "nodev"},
		})
		var m any
		_ = json.Unmarshal(b, &m)
		d["mounts"] = append(mounts, m)
	}
	a := annotations(d)
	if a == nil {
		a = map[string]any{}
		d["annotations"] = a
	}
	a[AnnotationWrapped] = "true"
	return true, save(path, d, mode)
}

// RewriteProcess wraps the args of an exec process file (a bare runtime-spec Process).
func RewriteProcess(path string, o Options) (bool, error) {
	d, mode, err := load(path)
	if err != nil {
		return false, err
	}
	changed, err := rewriteArgs(d, o)
	if err != nil || !changed {
		return false, err
	}
	return true, save(path, d, mode)
}
