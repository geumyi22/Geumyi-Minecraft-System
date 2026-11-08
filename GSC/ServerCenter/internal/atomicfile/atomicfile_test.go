package atomicfile

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

func leftovers(t *testing.T, path string) []string {
	t.Helper()
	m, err := filepath.Glob(filepath.Join(filepath.Dir(path), TempPattern(path)))
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestWriteFileReplacesAndLeavesNoTemp(t *testing.T) {
	p := filepath.Join(t.TempDir(), "server.json")
	if err := os.WriteFile(p, []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(p, []byte("new"), 0600); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(p)
	if string(got) != "new" {
		t.Fatalf("got %q", got)
	}
	if l := leftovers(t, p); len(l) != 0 {
		t.Fatalf("leftover temp files: %v", l)
	}
}

func TestLegacyFixedTempNamesAreNeverOpened(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "agent.properties")
	legacy := []string{p + ".tmp", p + ".gsc.tmp", p + ".new", p + ".part"}
	for _, l := range legacy {
		if err := os.WriteFile(l, []byte("PREPLANTED"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := WriteFile(p, []byte("secret=1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, l := range legacy {
		b, err := os.ReadFile(l)
		if err != nil || string(b) != "PREPLANTED" {
			t.Fatalf("legacy temp %s was touched: %v %q", filepath.Base(l), err, b)
		}
	}
}

func TestPreplantedSymlinkAtLegacyNameIsNotFollowed(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink creation needs a privilege on Windows; covered by the legacy-name test")
	}
	dir := t.TempDir()
	victim := filepath.Join(t.TempDir(), "victim.txt")
	if err := os.WriteFile(victim, []byte("victim"), 0600); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, "automations.json")
	if err := os.Symlink(victim, p+".tmp"); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(p, []byte("[]"), 0600); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(victim); string(b) != "victim" {
		t.Fatalf("symlink target was overwritten: %q", b)
	}
}

func TestFillErrorPreservesDestination(t *testing.T) {
	p := filepath.Join(t.TempDir(), "backup.zip")
	if err := os.WriteFile(p, []byte("previous-good"), 0644); err != nil {
		t.Fatal(err)
	}
	boom := errors.New("sha mismatch")
	err := WriteFrom(p, 0644, func(w io.Writer) error {
		_, _ = w.Write([]byte("partial"))
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("want fill error, got %v", err)
	}
	if b, _ := os.ReadFile(p); string(b) != "previous-good" {
		t.Fatalf("destination changed: %q", b)
	}
	if l := leftovers(t, p); len(l) != 0 {
		t.Fatalf("leftover temp files: %v", l)
	}
}

func TestReplaceFailurePreservesDestinationAndCleansTemp(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "trusted-devices.json")
	if err := os.Mkdir(p, 0700); err != nil { // a directory cannot be replaced by a file
		t.Fatal(err)
	}
	keep := filepath.Join(p, "keep.txt")
	if err := os.WriteFile(keep, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(p, []byte("x"), 0600); err == nil {
		t.Fatal("expected replace failure")
	}
	if b, _ := os.ReadFile(keep); string(b) != "keep" {
		t.Fatalf("destination changed: %q", b)
	}
	if l := leftovers(t, p); len(l) != 0 {
		t.Fatalf("leftover temp files: %v", l)
	}
}

func TestMissingDirectoryFailsWithoutSideEffects(t *testing.T) {
	p := filepath.Join(t.TempDir(), "absent", "x.json")
	if err := WriteFile(p, []byte("x"), 0600); err == nil {
		t.Fatal("expected error for missing directory (callers must create it explicitly)")
	}
}

func TestConcurrentWritersNeverPublishTornContent(t *testing.T) {
	p := filepath.Join(t.TempDir(), "control-jobs.json")
	payloads := make([][]byte, 16)
	for i := range payloads {
		payloads[i] = bytes.Repeat([]byte(fmt.Sprintf("%02d", i)), 4096)
	}
	var wg sync.WaitGroup
	errs := make(chan error, len(payloads))
	for _, b := range payloads {
		wg.Add(1)
		go func(b []byte) {
			defer wg.Done()
			errs <- WriteFile(p, b, 0600)
		}(b)
	}
	wg.Wait()
	close(errs)
	ok := 0
	for err := range errs {
		if err == nil {
			ok++
		}
	}
	if ok == 0 {
		t.Fatal("no writer succeeded")
	}
	got, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	match := false
	for _, b := range payloads {
		if bytes.Equal(got, b) {
			match = true
		}
	}
	if !match {
		t.Fatal("published content is not exactly one writer's payload")
	}
	if l := leftovers(t, p); len(l) != 0 {
		t.Fatalf("leftover temp files: %v", l)
	}
}

func TestPermissionIsApplied(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows Chmod only toggles the read-only attribute; DACL is inherited")
	}
	p := filepath.Join(t.TempDir(), "agent.properties")
	if err := WriteFile(p, []byte("a"), 0600); err != nil {
		t.Fatal(err)
	}
	st, _ := os.Stat(p)
	if st.Mode().Perm() != 0600 {
		t.Fatalf("perm %v", st.Mode().Perm())
	}
}
