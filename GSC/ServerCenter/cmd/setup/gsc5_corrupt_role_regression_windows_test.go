//go:build windows

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGSC5HostPresenceOverrulesStaleRole(t *testing.T) {
	for _, tc := range []struct {
		name string
		role int
		service, task, binary, config, want bool
	}{
		{"fresh", 0, false, false, false, false, false},
		{"clean-client", 2, false, false, false, false, false},
		{"declared-server", 3, false, false, false, false, true},
		{"service-despite-client-role", 2, true, false, false, false, true},
		{"task-despite-missing-role", 0, false, true, false, false, true},
		{"binary-and-config", 2, false, false, true, true, true},
		{"orphan-binary-only", 2, false, false, true, false, false},
		{"config-only", 0, false, false, false, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := gsc5HostEvidenceRequiresMigration(tc.role, tc.service, tc.task, tc.binary, tc.config)
			if got != tc.want {
				t.Fatalf("migration evidence=%v want %v", got, tc.want)
			}
		})
	}
}

func TestGSC5ActualMalformedRoleFixtureFailsBeforeMutation(t *testing.T) {
	// Synthetic copy of the user's reported invalid syntax. No real role file
	// or service is accessed. Windows Host binary+server.json are disposable
	// marker bytes to force the existing-Host path when role.json is broken.
	malformed := `{
  "version": "4.2.4",
  "role": 3,
  "role_name": "????,
  "updated_at": "2026-10-03T14:55:36+09:00",
  "dedicated_profile_active": false
}`
	gsc5AssertRejectedInstallFixture(t, malformed, "role state")
}

func TestGSC5StaleClientOnlyRoleCannotMaskExistingHost(t *testing.T) {
	validButWrong := `{"version":"4.2.4","role":2,"role_name":"client","dedicated_profile_active":false}`
	gsc5AssertRejectedInstallFixture(t, validButWrong, "Host")
}

func gsc5AssertRejectedInstallFixture(t *testing.T, stored string, expectedMessage string) {
	t.Helper()
	root := t.TempDir()
	dataDir := filepath.Join(root, "GeumyiServerCenter")
	installDir := filepath.Join(root, "Existing-GSC")
	if err := os.MkdirAll(dataDir, 0700); err != nil { t.Fatal(err) }
	if err := os.MkdirAll(installDir, 0700); err != nil { t.Fatal(err) }
	rolePath := filepath.Join(dataDir, "role.json")
	configPath := filepath.Join(dataDir, "server.json")
	hostPath := filepath.Join(installDir, "GeumyiServerHost.exe")
	for path, bytes := range map[string]string{
		rolePath: stored,
		configPath: `{"api_token":"synthetic-never-real","servers":[]}`,
		hostPath: "SYNTHETIC-NOT-AN-EXE",
	} {
		if err := os.WriteFile(path, []byte(bytes), 0600); err != nil { t.Fatal(err) }
	}
	t.Setenv("PROGRAMDATA", root)

	progressMu.Lock()
	original := prog
	prog = ProgressState{}
	progressMu.Unlock()
	t.Cleanup(func() {
		progressMu.Lock()
		prog = original
		progressMu.Unlock()
	})

	doInstall(InstallOptions{Role: 3, InstallDir: installDir})
	progressMu.RLock()
	p := prog
	progressMu.RUnlock()
	if !p.Done || p.Error == "" || !strings.Contains(p.Error, expectedMessage) {
		t.Fatalf("unsafe install not rejected: done=%v error=%q", p.Done, p.Error)
	}
	for path, expected := range map[string]string{
		rolePath: stored,
		configPath: `{"api_token":"synthetic-never-real","servers":[]}`,
		hostPath: "SYNTHETIC-NOT-AN-EXE",
	} {
		got, err := os.ReadFile(path)
		if err != nil || string(got) != expected {
			t.Fatalf("rejected install changed %s: %v", filepath.Base(path), err)
		}
	}
	for _, dir := range []string{dataDir, installDir} {
		entries, err := os.ReadDir(dir)
		if err != nil { t.Fatal(err) }
		if (dir == dataDir && len(entries) != 2) || (dir == installDir && len(entries) != 1) {
			t.Fatalf("blocked installer produced unexpected files in %s: %d", filepath.Base(dir), len(entries))
		}
	}
}
