//go:build windows

package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"geumyi/servercenter/internal/atomicfile"
)

// A pre-created "helper-<stamp>" (what an unprivileged user could plant in an
// inherited-create ProgramData folder) must never be reused as staging.
func TestNewExclusiveDirNeverReusesPredictableName(t *testing.T) {
	parent := filepath.Join(t.TempDir(), "Staging", "GSC")
	legacy := filepath.Join(parent, "helper-20261012-021000")
	if err := os.MkdirAll(legacy, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(legacy, "GeumyiServerHost.exe")
	if err := os.WriteFile(marker, []byte("PLANTED"), 0600); err != nil {
		t.Fatal(err)
	}
	a, err := newExclusiveDir(parent, "helper-20261012-021000-")
	if err != nil {
		t.Fatal(err)
	}
	b, err := newExclusiveDir(parent, "helper-20261012-021000-")
	if err != nil {
		t.Fatal(err)
	}
	if strings.EqualFold(a, legacy) || strings.EqualFold(b, legacy) || strings.EqualFold(a, b) {
		t.Fatalf("exclusive dirs not unique: %s %s legacy=%s", a, b, legacy)
	}
	if got, _ := os.ReadFile(marker); string(got) != "PLANTED" {
		t.Fatal("planted directory content was touched")
	}
}

func TestNewExclusiveDirRefusesJunctionParent(t *testing.T) {
	base := t.TempDir()
	target := filepath.Join(base, "elsewhere")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "GSC")
	out, err := exec.Command("cmd.exe", "/d", "/c", "mklink", "/J", link, target).CombinedOutput()
	if err != nil {
		t.Skipf("cannot create junction on this runner: %v %s", err, out)
	}
	if _, err := newExclusiveDir(link, "helper-x-"); err == nil {
		t.Fatal("junction parent was accepted")
	}
	if es, _ := os.ReadDir(target); len(es) != 0 {
		t.Fatalf("something was created through the junction: %d entries", len(es))
	}
}

func TestWriteEmbeddedStrictIgnoresPreplantedTempAndReplacesAtomically(t *testing.T) {
	dir := t.TempDir()
	dst := filepath.Join(dir, "GeumyiServerCenter.ico")
	if err := os.WriteFile(dst+".tmp", []byte("PREPLANTED"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dst, []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := writeEmbeddedStrict("GeumyiServerCenter.ico", dst); err != nil {
		t.Fatal(err)
	}
	want, _ := payload.ReadFile("payload/GeumyiServerCenter.ico")
	if got, _ := os.ReadFile(dst); !bytes.Equal(got, want) {
		t.Fatal("destination is not the embedded payload")
	}
	if got, _ := os.ReadFile(dst + ".tmp"); string(got) != "PREPLANTED" {
		t.Fatal("legacy predictable temp was opened")
	}
	if m, _ := filepath.Glob(filepath.Join(dir, atomicfile.TempPattern(dst))); len(m) != 0 {
		t.Fatalf("temp residue: %v", m)
	}
}

func TestMustExtractIgnoresPreplantedNewFile(t *testing.T) {
	dir := t.TempDir()
	dst := filepath.Join(dir, "agent.properties")
	if err := os.WriteFile(dst+".new", []byte("PREPLANTED"), 0600); err != nil {
		t.Fatal(err)
	}
	mustExtract("payload/agent.properties.managed", dst)
	want, _ := payload.ReadFile("payload/agent.properties.managed")
	if got, _ := os.ReadFile(dst); !bytes.Equal(got, want) {
		t.Fatal("agent.properties not extracted from payload")
	}
	if got, _ := os.ReadFile(dst + ".new"); string(got) != "PREPLANTED" {
		t.Fatal("legacy predictable .new file was opened")
	}
}

func TestCopyFileStrictKeepsDestinationWhenSourceMissing(t *testing.T) {
	dir := t.TempDir()
	dst := filepath.Join(dir, "GeumyiServerHost.exe")
	if err := os.WriteFile(dst, []byte("current-host"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := copyFileStrict(filepath.Join(dir, "missing.exe"), dst, 0755); err == nil {
		t.Fatal("expected error")
	}
	if got, _ := os.ReadFile(dst); string(got) != "current-host" {
		t.Fatal("current binary changed on failure")
	}
}
