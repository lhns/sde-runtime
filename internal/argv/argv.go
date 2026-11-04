// Package argv finds the subcommand of an OCI runtime (runc, crun) command line.
package argv

import "strings"

// Flags that take a value. Unknown flags are treated as booleans.
var globalValue = set("root", "log", "log-format", "log-level", "criu", "rootless", "cgroup-manager", "log-file")

var subValue = map[string]map[string]bool{
	"create": set("bundle", "b", "console-socket", "pid-file", "preserve-fds"),
	"run":    set("bundle", "b", "console-socket", "pid-file", "preserve-fds"),
	"exec": set("process", "p", "console-socket", "pid-file", "cwd", "env", "e", "user", "u",
		"additional-gids", "g", "process-label", "apparmor", "cap", "c", "preserve-fds", "cgroup"),
}

// Cmd is a parsed runtime command line (without argv[0]).
type Cmd struct {
	Sub        string   // "" if there is none
	Global     []string // flags before the subcommand, verbatim
	Bundle     string   // create/run: --bundle/-b
	Process    string   // exec: --process/-p
	Positional []string // after the flags: container id, then inline exec args
}

func set(names ...string) map[string]bool {
	m := map[string]bool{}
	for _, n := range names {
		m[n] = true
	}
	return m
}

// flag reports the flag's name and whether the next token is its value.
func flag(tok string, takesValue map[string]bool) (name, inline string, hasInline, wantsNext bool) {
	name = strings.TrimLeft(tok, "-")
	if i := strings.IndexByte(name, '='); i >= 0 {
		return name[:i], name[i+1:], true, false
	}
	return name, "", false, takesValue[name]
}

func Parse(args []string) Cmd {
	var c Cmd
	i := 0
	for ; i < len(args); i++ {
		tok := args[i]
		if tok == "--" || !strings.HasPrefix(tok, "-") || tok == "-" {
			break
		}
		_, _, _, next := flag(tok, globalValue)
		if next && i+1 < len(args) {
			i++
		}
	}
	c.Global = args[:i]
	if i >= len(args) || args[i] == "--" {
		return c
	}
	c.Sub = args[i]
	vals := subValue[c.Sub]
	for i++; i < len(args); i++ {
		tok := args[i]
		if tok == "--" {
			c.Positional = append(c.Positional, args[i+1:]...)
			break
		}
		if !strings.HasPrefix(tok, "-") || tok == "-" {
			c.Positional = append(c.Positional, tok)
			// After the id, the rest of exec is the inline command.
			if c.Sub == "exec" {
				c.Positional = append(c.Positional, args[i+1:]...)
				break
			}
			continue
		}
		name, val, has, next := flag(tok, vals)
		if next && i+1 < len(args) {
			i++
			val, has = args[i], true
		}
		if !has {
			continue
		}
		switch name {
		case "bundle", "b":
			c.Bundle = val
		case "process", "p":
			c.Process = val
		}
	}
	return c
}

// ID is the container id, or "" if absent.
func (c Cmd) ID() string {
	if len(c.Positional) == 0 {
		return ""
	}
	return c.Positional[0]
}
