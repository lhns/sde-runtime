package wrapper

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/lhns/sde-runtime/internal/spec"
)

type env struct {
	t      *testing.T
	dir    string
	sde    string
	bundle string
	conf   string
	logs   []string
	v3     bool
	state  func(string, []string, string) (string, error)
}

const appCfg = `{"process":{"args":["/app"]},"annotations":{"io.kubernetes.cri.container-type":"container"}}`

func newEnv(t *testing.T) *env {
	dir := t.TempDir()
	e := &env{t: t, dir: dir, sde: filepath.Join(dir, "sde"), bundle: filepath.Join(dir, "b"), conf: filepath.Join(dir, "config.toml")}
	must(os.MkdirAll(e.sde, 0o755))
	must(os.MkdirAll(e.bundle, 0o755))
	must(os.WriteFile(filepath.Join(e.sde, "sde64"), nil, 0o755))
	must(os.WriteFile(filepath.Join(e.bundle, "config.json"), []byte(appCfg), 0o644))
	e.config(fmt.Sprintf("real_runtime = %q\nbundle_path = %q\nlog_file = \"\"\n", "/real/runc", filepath.ToSlash(e.sde)))
	return e
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func (e *env) config(s string) { must(os.WriteFile(e.conf, []byte(s), 0o644)) }

func (e *env) prepare(args ...string) string {
	return Prepare(args, Deps{
		ConfigPath: e.conf,
		HostV3:     func() bool { return e.v3 },
		Logf:       func(_, f string, a ...any) { e.logs = append(e.logs, fmt.Sprintf(f, a...)) },
		State:      e.state,
		Getwd:      func() (string, error) { return e.bundle, nil },
	})
}

func (e *env) cfgBytes() string {
	b, _ := os.ReadFile(filepath.Join(e.bundle, "config.json"))
	return string(b)
}

func (e *env) wrapped() bool { return strings.Contains(e.cfgBytes(), spec.SDEBinary) }

func (e *env) lastLog() string {
	if len(e.logs) == 0 {
		return ""
	}
	return e.logs[len(e.logs)-1]
}

func TestCreateWraps(t *testing.T) {
	e := newEnv(t)
	if got := e.prepare("--root", "/r", "create", "--bundle", e.bundle, "c1"); got != "/real/runc" {
		t.Fatal(got)
	}
	if !e.wrapped() || !strings.Contains(e.lastLog(), "wrapped") {
		t.Fatalf("%s %v", e.cfgBytes(), e.logs)
	}
}

func TestRunUsesCwdWithoutBundleFlag(t *testing.T) {
	e := newEnv(t)
	e.prepare("run", "c1")
	if !e.wrapped() {
		t.Fatal("not wrapped")
	}
}

func TestHostCheckInjectable(t *testing.T) {
	e := newEnv(t)
	e.v3 = true
	e.prepare("create", "-b", e.bundle, "c1")
	if e.wrapped() || !strings.Contains(e.lastLog(), "natively") {
		t.Fatalf("capable host must pass through: %v", e.logs)
	}
	e.config(fmt.Sprintf("real_runtime = \"/real/runc\"\nbundle_path = %q\nlog_file = \"\"\nforce_on_capable_host = true\n", filepath.ToSlash(e.sde)))
	e.prepare("create", "-b", e.bundle, "c1")
	if !e.wrapped() {
		t.Fatal("force_on_capable_host ignored")
	}
}

func TestSandboxNotWrapped(t *testing.T) {
	e := newEnv(t)
	sb := `{"process":{"args":["/pause"]},"annotations":{"io.kubernetes.cri.container-type":"sandbox"}}`
	must(os.WriteFile(filepath.Join(e.bundle, "config.json"), []byte(sb), 0o644))
	e.prepare("create", "-b", e.bundle, "c1")
	if e.cfgBytes() != sb {
		t.Fatal("sandbox modified")
	}
}

func TestOtherSubcommandsUntouchedAndSilent(t *testing.T) {
	e := newEnv(t)
	for _, c := range [][]string{{"state", "c1"}, {"start", "c1"}, {"kill", "c1", "TERM"}, {"delete", "c1"}, {"features"}, {"--version"}, {}} {
		if got := e.prepare(c...); got != "/real/runc" {
			t.Fatal(got)
		}
	}
	if e.cfgBytes() != appCfg || len(e.logs) != 0 {
		t.Fatalf("hot path touched things: %v", e.logs)
	}
}

func TestFailOpenBrokenConfig(t *testing.T) {
	e := newEnv(t)
	e.config("this = = not toml")
	got := e.prepare("create", "-b", e.bundle, "c1")
	if got != "/var/lib/k0s/bin/runc" || e.cfgBytes() != appCfg || !strings.Contains(e.lastLog(), "passing through") {
		t.Fatalf("%q %v", got, e.logs)
	}
}

func TestMissingConfigUsesDefaults(t *testing.T) {
	e := newEnv(t)
	must(os.Remove(e.conf))
	if got := e.prepare("state", "c1"); got != "/var/lib/k0s/bin/runc" || len(e.logs) != 0 {
		t.Fatal(got, e.logs)
	}
}

func TestFailOpenMissingBundle(t *testing.T) {
	e := newEnv(t)
	must(os.Remove(filepath.Join(e.sde, "sde64")))
	e.prepare("create", "-b", e.bundle, "c1")
	if e.cfgBytes() != appCfg || !strings.Contains(e.lastLog(), "SDE bundle missing") {
		t.Fatal(e.logs)
	}
}

func TestFailOpenBrokenSpec(t *testing.T) {
	e := newEnv(t)
	must(os.WriteFile(filepath.Join(e.bundle, "config.json"), []byte("{oops"), 0o644))
	e.prepare("create", "-b", e.bundle, "c1")
	if e.cfgBytes() != "{oops" || !strings.Contains(e.lastLog(), "passing through") {
		t.Fatal(e.logs)
	}
}

func (e *env) execFixture(wrapped bool) string {
	if wrapped {
		e.prepare("create", "-b", e.bundle, "c1")
	}
	proc := filepath.Join(e.dir, "process.json")
	must(os.WriteFile(proc, []byte(`{"args":["sh","-c","id"],"future":1}`), 0o644))
	var gotGlobal []string
	e.state = func(real string, global []string, id string) (string, error) {
		gotGlobal = global
		if real != "/real/runc" || id != "c1" {
			return "", errors.New("bad args")
		}
		return e.bundle, nil
	}
	e.prepare("--root", "/r", "exec", "--process", proc, "--pid-file", "/p", "c1")
	if strings.Join(gotGlobal, " ") != "--root /r" {
		e.t.Fatalf("global flags not forwarded to state: %v", gotGlobal)
	}
	b, _ := os.ReadFile(proc)
	return string(b)
}

func TestExecMarkedContainerRewritten(t *testing.T) {
	e := newEnv(t)
	if got := e.execFixture(true); !strings.Contains(got, `"/sde/sde64","-hsw","--","sh"`) || !strings.Contains(got, `"future":1`) {
		t.Fatal(got)
	}
}

func TestExecUnmarkedContainerUntouched(t *testing.T) {
	e := newEnv(t)
	if got := e.execFixture(false); got != `{"args":["sh","-c","id"],"future":1}` {
		t.Fatal(got)
	}
}

func TestExecFailOpen(t *testing.T) {
	e := newEnv(t)
	e.prepare("create", "-b", e.bundle, "c1")
	proc := filepath.Join(e.dir, "process.json")
	const orig = `{"args":["sh"]}`
	must(os.WriteFile(proc, []byte(orig), 0o644))
	e.state = func(string, []string, string) (string, error) { return "", errors.New("no such container") }
	e.prepare("exec", "--process", proc, "c1")
	if b, _ := os.ReadFile(proc); string(b) != orig || !strings.Contains(e.lastLog(), "passing through") {
		t.Fatal(string(b), e.logs)
	}
	e.state = func(string, []string, string) (string, error) { return e.bundle, nil }
	e.prepare("exec", "c1", "sh") // inline args: no process file
	if !strings.Contains(e.lastLog(), "inline") {
		t.Fatal(e.logs)
	}
}

func TestExecOnCapableHostSkipsStateCall(t *testing.T) {
	e := newEnv(t)
	e.v3 = true
	e.state = func(string, []string, string) (string, error) { t.Fatal("state called"); return "", nil }
	e.prepare("exec", "--process", "/x", "c1")
}
