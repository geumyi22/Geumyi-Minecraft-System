//go:build windows

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestUpdateReplacementPreservesExistingSiblingsAndDirectories(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "source")
	dst := filepath.Join(root, "target")
	if err := os.WriteFile(src, []byte("release data"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{dst, dst + ".gsc-new", dst + ".tmp"} {
		if err := os.WriteFile(p, []byte("existing"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := copyFileStrict(src, dst, 0600); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(dst)
	if err != nil || string(data) != "release data" {
		t.Fatalf("update failed: %q %v", data, err)
	}
	writeSelfUpdateReportAt(dst, selfUpdateReport{Status: "test"})
	for _, suffix := range []string{".gsc-new", ".tmp"} {
		data, err := os.ReadFile(dst + suffix)
		if err != nil || string(data) != "existing" {
			t.Errorf("sibling %s changed: %q %v", suffix, data, err)
		}
	}
	targetDir := filepath.Join(root, "existing-directory")
	if err := os.Mkdir(targetDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := copyFileStrict(src, targetDir, 0600); err == nil {
		t.Error("copy replaced a directory")
	}
	info, err := os.Stat(targetDir)
	if err != nil || !info.IsDir() {
		t.Fatalf("expected original directory: %v", err)
	}
}
