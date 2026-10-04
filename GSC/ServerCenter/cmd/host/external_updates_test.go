package main

import "testing"

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
