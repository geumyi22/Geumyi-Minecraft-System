package velocitylifecycle

import (
	"go/parser"
	"go/token"
	"path/filepath"
	"runtime"
	"strconv"
	"testing"
)

// Avoid drifting a harmless simulator into a live control implementation by
// accidentally importing OS process, file mutation or network primitives.
func TestPhaseCModulesHaveNoLiveProcessOrNetworkImports(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot resolve test source directory")
	}
	root := filepath.Dir(thisFile)
	sources := []string{
		filepath.Join(root, "lifecycle.go"),
		filepath.Join(root, "maintenance_lease.go"),
		filepath.Join(root, "task_policy_report.go"),
		filepath.Join(root, "task_instance_report.go"),
		filepath.Clean(filepath.Join(root, "..", "velocitybridge", "auth.go")),
	}
	forbidden := map[string]bool{
		"os": true,
		"os/exec": true,
		"net": true,
		"net/http": true,
		"net/rpc": true,
		"net/url": true,
		"syscall": true,
		"unsafe": true,
		"plugin": true,
	}
	for _, filename := range sources {
		t.Run(filepath.Base(filename), func(t *testing.T) {
			file, err := parser.ParseFile(token.NewFileSet(), filename, nil, parser.AllErrors|parser.ImportsOnly)
			if err != nil {
				t.Fatalf("source parse failure: %v", err)
			}
			for _, im := range file.Imports {
				path, err := strconv.Unquote(im.Path.Value)
				if err != nil || forbidden[path] {
					t.Fatalf("isolated prototype imported live control dependency %q", im.Path.Value)
				}
			}
		})
	}
}
