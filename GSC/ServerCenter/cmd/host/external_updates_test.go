package main

import (
	"path/filepath"
	"runtime"
	"testing"
)

func TestExternalParseSHA256Digest(t *testing.T) {
	good := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	for _, in := range []string{good, "sha256:" + good, " SHA256:" + good + " "} {
		if got := parseSHA256Digest(in); got != good {
			t.Fatalf("parseSHA256Digest(%q)=%q", in, got)
		}
	}
	for _, in := range []string{"", "sha256:abc", "g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"} {
		if got := parseSHA256Digest(in); got != "" {
			t.Fatalf("invalid digest accepted: %q => %q", in, got)
		}
	}
}

func TestExternalCurrentAgainstSHA(t *testing.T) {
	sha := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	status, _ := externalCurrentAgainstSHA(map[string]string{"wild": sha, "playground": sha, "other": sha}, sha)
	if status != "current" {
		t.Fatalf("all matching should be current, got %s", status)
	}
	status, _ = externalCurrentAgainstSHA(map[string]string{"wild": sha, "playground": "missing", "other": sha}, sha)
	if status != "update" {
		t.Fatalf("missing target should need update, got %s", status)
	}
	status, _ = externalCurrentAgainstSHA(map[string]string{"wild": sha}, "")
	if status != "unknown" {
		t.Fatalf("missing trusted hash should be unknown, got %s", status)
	}
}

func TestExternalStageNameRejectsNonJar(t *testing.T) {
	if _, err := safeExternalStageName("../evil.exe"); err == nil {
		t.Fatal("non-JAR stage name accepted")
	}
	got, err := safeExternalStageName("../Geyser-Velocity.jar")
	if err != nil || got != "Geyser-Velocity.jar" {
		t.Fatalf("safe basename failed: got=%q err=%v", got, err)
	}
}


func TestExternalPathWithin(t *testing.T) {
	base := `C:\\ProgramData\\GeumyiServerCenter\\Staging\\External`
	if runtime.GOOS == "windows" {
		if !externalPathWithin(base, filepath.Join(base, "20261006-010000")) {
			t.Fatal("valid stage child rejected")
		}
		if externalPathWithin(base, filepath.Join(base, "..", "escape")) {
			t.Fatal("path traversal accepted")
		}
		return
	}
	base = "/tmp/gsc/Staging/External"
	if !externalPathWithin(base, filepath.Join(base, "20261006-010000")) {
		t.Fatal("valid stage child rejected")
	}
	if externalPathWithin(base, filepath.Join(base, "..", "escape")) {
		t.Fatal("path traversal accepted")
	}
}

func TestExternalProxyTargetsMatchDay10PublicPorts(t *testing.T) {
	want := map[string][2]int{
		"wild": {25565, 19132},
		"playground": {25566, 19133},
		"other": {25567, 19134},
	}
	if len(day11ExternalProxyTargets) != 3 {
		t.Fatalf("unexpected proxy target count: %d", len(day11ExternalProxyTargets))
	}
	for _, x := range day11ExternalProxyTargets {
		p, ok := want[x.ID]
		if !ok || x.PublicJava != p[0] || x.PublicBedrock != p[1] || x.TaskName == "" {
			t.Fatalf("bad proxy target: %+v", x)
		}
	}
}
