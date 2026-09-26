//go:build !windows

package javaruntime

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveExecutesShimAndUsesReportedHome(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "Program Files", "Java", "jdk-test")
	os.MkdirAll(filepath.Join(home, "bin"), 0755)
	actual := filepath.Join(home, "bin", "java")
	os.WriteFile(actual, []byte("#!/bin/sh\nexit 0\n"), 0700)
	shim := filepath.Join(root, "oracle-shim")
	os.WriteFile(shim, []byte("#!/bin/sh\nprintf '%s\\n' '    java.home = "+home+"' '    java.version = 26.0.2' >&2\n"), 0700)
	r, e := Resolve(shim)
	if e != nil {
		t.Fatal(e)
	}
	if r.Home != home || r.Executable != actual {
		t.Fatalf("shim was used as JAVA_HOME: %+v", r)
	}
}
