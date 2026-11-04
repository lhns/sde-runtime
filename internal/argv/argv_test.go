package argv

import (
	"reflect"
	"testing"
)

func TestParse(t *testing.T) {
	cases := []struct {
		name string
		in   []string
		want Cmd
	}{
		{"empty", nil, Cmd{}},
		{"version only", []string{"--version"}, Cmd{Global: []string{"--version"}}},
		{"state", []string{"state", "c1"}, Cmd{Sub: "state", Positional: []string{"c1"}}},
		{"global value spaced", []string{"--root", "/run/runc", "--log", "/l", "delete", "-f", "c1"},
			Cmd{Sub: "delete", Global: []string{"--root", "/run/runc", "--log", "/l"}, Positional: []string{"c1"}}},
		{"global inline and bool", []string{"--root=/r", "--debug", "--systemd-cgroup", "kill", "c1", "TERM"},
			Cmd{Sub: "kill", Global: []string{"--root=/r", "--debug", "--systemd-cgroup"}, Positional: []string{"c1", "TERM"}}},
		{"crun cgroup-manager", []string{"--cgroup-manager", "systemd", "start", "c1"},
			Cmd{Sub: "start", Global: []string{"--cgroup-manager", "systemd"}, Positional: []string{"c1"}}},
		{"create bundle", []string{"--root", "/r", "create", "--bundle", "/b", "--pid-file", "/p", "c1"},
			Cmd{Sub: "create", Global: []string{"--root", "/r"}, Bundle: "/b", Positional: []string{"c1"}}},
		{"create short and no pivot", []string{"create", "--no-pivot", "-b", "/b", "c1"},
			Cmd{Sub: "create", Bundle: "/b", Positional: []string{"c1"}}},
		{"run inline", []string{"run", "-b=/b", "-d", "c1"}, Cmd{Sub: "run", Bundle: "/b", Positional: []string{"c1"}}},
		{"create without bundle", []string{"create", "c1"}, Cmd{Sub: "create", Positional: []string{"c1"}}},
		{"exec process", []string{"exec", "--process", "/tmp/p.json", "--pid-file", "/x", "-d", "c1"},
			Cmd{Sub: "exec", Process: "/tmp/p.json", Positional: []string{"c1"}}},
		{"exec inline args", []string{"exec", "-t", "-e", "A=1", "c1", "sh", "-c", "id"},
			Cmd{Sub: "exec", Positional: []string{"c1", "sh", "-c", "id"}}},
		{"exec -- args", []string{"exec", "c1", "--", "ls"}, Cmd{Sub: "exec", Positional: []string{"c1", "--", "ls"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Parse(c.in)
			if len(got.Global) == 0 {
				got.Global = nil
			}
			if len(got.Positional) == 0 {
				got.Positional = nil
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("got %+v, want %+v", got, c.want)
			}
		})
	}
}

func TestID(t *testing.T) {
	if (Cmd{}).ID() != "" || Parse([]string{"state", "x"}).ID() != "x" {
		t.Fatal("ID")
	}
}
