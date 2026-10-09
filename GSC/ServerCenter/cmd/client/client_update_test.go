//go:build windows

package main

import "testing"

func TestClientVersionComparison(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"4.3.7", "4.3.8", -1},
		{"4.3.8", "4.3.8", 0},
		{"4.3.9", "4.3.8", 1},
		{"v4.3.8", "4.3.8+120", 0},
		{"4.3.8", "4.3.9-rc.1", -1},
		{"4.3.9-rc.1", "4.3.9", -1},
		{"4.3.9", "4.3.9-rc.1", 1},
		{"4.3.9-rc.2", "4.3.9-rc.10", -1},
		{"4.3.9-alpha", "4.3.9-rc.1", -1},
		{"4.3.9-rc.1", "4.3.9-rc.1+201", 0},
		{"4.3.9-rc.1", "4.3.8", 1},
		{"4.3.9-rc.2", "4.3.9-rc.2.1", -1},
	}
	for _, tc := range cases {
		got, err := compareClientVersions(tc.a, tc.b)
		if err != nil {
			t.Fatalf("%s vs %s: %v", tc.a, tc.b, err)
		}
		if got != tc.want {
			t.Fatalf("%s vs %s: got %d want %d", tc.a, tc.b, got, tc.want)
		}
	}
}

func TestClientVersionMalformedPrereleaseFailClosed(t *testing.T) {
	for _, target := range []string{
		"4.3.9-", "4.3.9-rc..1", "4.3.9-rc/1", "4.3.9-rc.01",
		"4.3.9-rc.0.", "4.3.9-alpha_%20",
	} {
		if _, err := compareClientVersions("4.3.8", target); err == nil {
			t.Errorf("malformed client target %q passed version check", target)
		}
	}
}

func TestClientUpdateRepositoryValidation(t *testing.T) {
	for _, good := range []string{
		"geumyi22/Geumyi-Minecraft-System",
		"owner_1/repo.name-2",
	} {
		if !validGitHubRepository(good) {
			t.Fatalf("valid repository rejected: %q", good)
		}
	}
	for _, bad := range []string{
		"",
		"owner",
		"owner/repo/extra",
		"owner/../repo",
		"owner/repo?x=1",
		"https://github.com/owner/repo",
	} {
		if validGitHubRepository(bad) {
			t.Fatalf("unsafe repository accepted: %q", bad)
		}
	}
}

func TestSafeClientUpdatePart(t *testing.T) {
	got := safeClientUpdatePart("system-2026.10.07/day11:client")
	if got != "system-2026.10.07_day11_client" {
		t.Fatalf("safeClientUpdatePart=%q", got)
	}
}
