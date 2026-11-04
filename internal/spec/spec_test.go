package spec

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

var opts = Options{BundlePath: "/opt/sde-bundle", Chip: "hsw", InitPaths: []string{"/sbin/docker-init", "/run/podman-init", "/dev/init"}}

func TestWrapArgs(t *testing.T) {
	cases := []struct {
		name    string
		in, out []string
		changed bool
	}{
		{"plain", []string{"/app", "-x"}, []string{"/sde/sde64", "-hsw", "--", "/app", "-x"}, true},
		{"empty", nil, nil, false},
		{"already", []string{"/sde/sde64", "-hsw", "--", "/app"}, []string{"/sde/sde64", "-hsw", "--", "/app"}, false},
		{"docker-init", []string{"/sbin/docker-init", "--", "/app"}, []string{"/sbin/docker-init", "--", "/sde/sde64", "-hsw", "--", "/app"}, true},
		{"podman-init flags", []string{"/run/podman-init", "-g", "--", "/app", "--", "x"}, []string{"/run/podman-init", "-g", "--", "/sde/sde64", "-hsw", "--", "/app", "--", "x"}, true},
		{"dev-init already", []string{"/dev/init", "--", "/sde/sde64", "-hsw", "--", "/app"}, []string{"/dev/init", "--", "/sde/sde64", "-hsw", "--", "/app"}, false},
		{"init without dashes wraps all", []string{"/dev/init", "/app"}, []string{"/sde/sde64", "-hsw", "--", "/dev/init", "/app"}, true},
		{"init only", []string{"/dev/init", "--"}, []string{"/dev/init", "--"}, false},
	}
	for _, c := range cases {
		got, ch := WrapArgs(c.in, opts)
		if ch != c.changed || !reflect.DeepEqual(got, c.out) {
			t.Errorf("%s: got %v %v, want %v %v", c.name, got, ch, c.out, c.changed)
		}
	}
}

func TestExtraArgsAndChip(t *testing.T) {
	o := opts
	o.Chip = "adl"
	o.ExtraArgs = []string{"-foo", "1"}
	got, _ := WrapArgs([]string{"/a"}, o)
	want := []string{"/sde/sde64", "-adl", "-foo", "1", "--", "/a"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%v", got)
	}
}

const cfg = `{"ociVersion":"1.0.2","futureField":{"a":[1,2.50,12345678901234567890]},"process":{"args":["/app","<&>"],"x-new":true},
"mounts":[{"destination":"/proc","type":"proc","source":"proc"}],"annotations":{"k":"v"},"linux":{"unknownThing":1}}`

func write(t *testing.T, s string) string {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(s), 0o640); err != nil {
		t.Fatal(err)
	}
	return p
}

func read(t *testing.T, p string) map[string]any {
	b, _ := os.ReadFile(p)
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func TestRewriteConfigPreservesAndIsIdempotent(t *testing.T) {
	p := write(t, cfg)
	ch, err := RewriteConfig(p, opts)
	if err != nil || !ch {
		t.Fatal(ch, err)
	}
	b1, _ := os.ReadFile(p)
	m := read(t, p)
	if !reflect.DeepEqual(m["futureField"], read(t, write(t, cfg))["futureField"]) {
		t.Fatal("unknown field changed")
	}
	for _, s := range []string{"12345678901234567890", "2.50", "<&>"} {
		if !strings.Contains(string(b1), s) {
			t.Fatalf("%s mangled: %s", s, b1)
		}
	}
	pr := m["process"].(map[string]any)
	if pr["x-new"] != true || m["linux"].(map[string]any)["unknownThing"].(float64) != 1 {
		t.Fatal("unknown nested field lost")
	}
	args := pr["args"].([]any)
	if args[0] != "/sde/sde64" || len(args) != 5 {
		t.Fatalf("%v", args)
	}
	mounts := m["mounts"].([]any)
	if len(mounts) != 2 || mounts[1].(map[string]any)["destination"] != "/sde" || mounts[1].(map[string]any)["source"] != "/opt/sde-bundle" {
		t.Fatalf("%v", mounts)
	}
	if w, _ := IsWrapped(p); !w {
		t.Fatal("not marked")
	}
	if m["annotations"].(map[string]any)["k"] != "v" {
		t.Fatal("annotation lost")
	}
	if st, _ := os.Stat(p); filepath.Separator == '/' && st.Mode().Perm() != 0o640 {
		t.Fatalf("mode %v", st.Mode())
	}
	ch, err = RewriteConfig(p, opts)
	b2, _ := os.ReadFile(p)
	if err != nil || ch || string(b1) != string(b2) {
		t.Fatal("not idempotent")
	}
	if entries, _ := os.ReadDir(filepath.Dir(p)); len(entries) != 1 {
		t.Fatal("temp file left behind")
	}
}

func TestRewriteConfigErrorsLeaveFileAlone(t *testing.T) {
	for _, s := range []string{`{not json`, `[]`, `{"process":{"args":[1]}}`, `{}`} {
		p := write(t, s)
		if ch, err := RewriteConfig(p, opts); ch || err == nil {
			t.Errorf("%s: %v %v", s, ch, err)
		}
		if b, _ := os.ReadFile(p); string(b) != s {
			t.Errorf("%s modified", s)
		}
	}
	if ch, err := RewriteConfig(filepath.Join(t.TempDir(), "none"), opts); ch || err == nil {
		t.Fatal("missing file")
	}
}

func TestExistingSDEMountNotDuplicated(t *testing.T) {
	p := write(t, `{"process":{"args":["/a"]},"mounts":[{"destination":"/sde","type":"bind","source":"/x"}]}`)
	if _, err := RewriteConfig(p, opts); err != nil {
		t.Fatal(err)
	}
	if n := len(read(t, p)["mounts"].([]any)); n != 1 {
		t.Fatal(n)
	}
}

func TestSandbox(t *testing.T) {
	p := write(t, `{"process":{"args":["/pause"]},"annotations":{"io.kubernetes.cri.container-type":"sandbox"}}`)
	if s, err := IsSandbox(p); !s || err != nil {
		t.Fatal(s, err)
	}
	p = write(t, `{"process":{"args":["/a"]},"annotations":{"io.kubernetes.cri.container-type":"container"}}`)
	if s, _ := IsSandbox(p); s {
		t.Fatal("container")
	}
}

func TestRewriteProcess(t *testing.T) {
	p := write(t, `{"args":["sh","-c","id"],"terminal":true,"future":1}`)
	ch, err := RewriteProcess(p, opts)
	if err != nil || !ch {
		t.Fatal(ch, err)
	}
	m := read(t, p)
	if m["future"].(float64) != 1 || m["terminal"] != true || m["args"].([]any)[0] != "/sde/sde64" {
		t.Fatalf("%v", m)
	}
	if ch, _ := RewriteProcess(p, opts); ch {
		t.Fatal("not idempotent")
	}
}
