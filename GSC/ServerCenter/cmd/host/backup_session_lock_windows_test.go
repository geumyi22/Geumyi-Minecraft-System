//go:build windows

package main

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

func TestBackupSkipsWindowsSessionLock(t *testing.T) {
	for _, scope := range []string{"world", "."} {
		t.Run(scope, func(t *testing.T) {
			dir := t.TempDir()
			world := filepath.Join(dir, "world")
			if err := os.MkdirAll(world, 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(world, "level.dat"), []byte("preserve-world-bytes"), 0600); err != nil {
				t.Fatal(err)
			}
			name, err := syscall.UTF16PtrFromString(filepath.Join(world, "session.lock"))
			if err != nil {
				t.Fatal(err)
			}
			h, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.CREATE_ALWAYS, syscall.FILE_ATTRIBUTE_NORMAL, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer syscall.CloseHandle(h)
			var buf bytes.Buffer
			zw := zip.NewWriter(&buf)
			if err := addPathToZip(zw, dir, scope); err != nil {
				t.Fatalf("runtime lock must not prevent a world backup: %v", err)
			}
			if err := zw.Close(); err != nil {
				t.Fatal(err)
			}
			zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
			if err != nil {
				t.Fatal(err)
			}
			found := false
			for _, f := range zr.File {
				if filepath.Base(f.Name) == "session.lock" {
					t.Fatal("runtime lock leaked into backup")
				}
				if f.Name == "world/level.dat" {
					found = true
				}
			}
			if !found {
				t.Fatal("world data was not backed up")
			}
		})
	}
}

func TestBackupStillRejectsLockedWorldData(t *testing.T) {
	dir := t.TempDir()
	name, err := syscall.UTF16PtrFromString(filepath.Join(dir, "level.dat"))
	if err != nil {
		t.Fatal(err)
	}
	h, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.CREATE_ALWAYS, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.CloseHandle(h)
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	if err := addPathToZip(zw, dir, "."); err == nil {
		t.Fatal("locked world data must fail closed, not be silently skipped")
	}
	_ = zw.Close()
}
