//go:build windows

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGSC5HostMigrationDecisionTable(t *testing.T) {
	stable := gsc5ExistingHostHealth{OK: true, Service: true, Version: "4.5.1", Generation: 4}
	beta := gsc5ExistingHostHealth{OK: true, Service: true, Version: version, Generation: 4}
	canary := gsc5ExistingHostHealth{OK: true, Service: true, Version: "4.5.2", Generation: 4}
	cases := []struct {
		name string
		role int
		stored string
		health gsc5ExistingHostHealth
		known bool
		allowed bool
	}{
		{"fresh-install", 0, "", gsc5ExistingHostHealth{}, false, true},
		{"client-only", 2, "4.5.2", canary, true, true},
		{"stable-base-existing-host", 1, "4.5.1", stable, true, true},
		{"combined-stable", 3, "", stable, true, true},
		{"same-beta-reinstall", 1, version, beta, true, true},
		{"canary-running", 1, "4.5.1", canary, true, false},
		{"stale-role-version-even-with-stable-health", 3, "4.2.4", stable, true, false},
		{"stale-role-version-even-with-beta-health", 3, "4.2.4", beta, true, false},
		{"canary-stored-down", 1, "4.5.2", gsc5ExistingHostHealth{}, false, false},
		{"canary-stored-conflicts-with-health", 1, "4.5.2-velocity", stable, true, false},
		{"host-unreachable", 1, "4.5.1", gsc5ExistingHostHealth{}, false, false},
		{"host-version-unknown", 1, "4.5.1", gsc5ExistingHostHealth{OK: true, Service: true, Version: "4.3.8", Generation: 4}, true, false},
		{"spoof-nonservice", 1, "4.5.1", gsc5ExistingHostHealth{OK: true, Service: false, Version: "4.5.1", Generation: 4}, true, false},
		{"bad-health-generation", 1, "4.5.1", gsc5ExistingHostHealth{OK: true, Service: true, Version: "4.5.1", Generation: 5}, true, false},
		{"unverified-health-flag", 1, "4.5.1", stable, false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := gsc5MigrationDecision(tc.role, tc.stored, tc.health, tc.known)
			if (err == nil) != tc.allowed {
				t.Fatalf("decision allowed=%t, wanted=%t", err == nil, tc.allowed)
			}
		})
	}
}

func TestGSC5ExistingHostHealthParsing(t *testing.T) {
	for _, tc := range []struct {
		name string
		code int
		body string
		known bool
	}{
		{"real-shape", 200, `{"ok":true,"version":"4.5.1","service":true,"generation":4}`, true},
		{"malformed", 200, `{"ok":true,`, false},
		{"server-error", 503, `{"ok":true}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.code)
				_, _ = w.Write([]byte(tc.body))
			}))
			defer server.Close()
			got, err := gsc5ReadExistingHostHealth(server.Client(), server.URL)
			if (err == nil) != tc.known {
				t.Fatalf("response accepted=%v expected=%v", err == nil, tc.known)
			}
			if tc.name == "real-shape" && got.Version != "4.5.1" {
				t.Fatalf("unexpected host version %q", got.Version)
			}
		})
	}
}

func TestGSC5CanaryInstallStopsBeforeAnyServiceOrInstallFileChanges(t *testing.T) {
	dir := t.TempDir()
	dataDir := filepath.Join(dir, "GeumyiServerCenter")
	if err := os.MkdirAll(dataDir, 0700); err != nil {
		t.Fatal(err)
	}
	role := RoleState{Role: 1, Version: "4.5.2"}
	b, err := json.Marshal(role)
	if err != nil {
		t.Fatal(err)
	}
	rolePath := filepath.Join(dataDir, roleStateFile)
	if err := os.WriteFile(rolePath, b, 0600); err != nil {
		t.Fatal(err)
	}
	installDir := filepath.Join(dir, "NEVER-INSTALLED")
	t.Setenv("PROGRAMDATA", dir)
	progressMu.Lock()
	before := prog
	prog = ProgressState{}
	progressMu.Unlock()
	t.Cleanup(func() {
		progressMu.Lock()
		prog = before
		progressMu.Unlock()
	})

	// No live server URL, Windows service operation, real Java or secrets.
	// Canary is rejected using only synthetic role state; even the Host
	// health endpoint is not contacted.
	doInstall(InstallOptions{Role: 1, InstallDir: installDir})
	progressMu.RLock()
	state := prog
	progressMu.RUnlock()
	if !state.Done || state.Error == "" || !strings.Contains(state.Error, "Canary") {
		t.Fatalf("Canary install was not blocked: done=%v status=%q", state.Done, state.Status)
	}
	if _, err := os.Stat(installDir); !os.IsNotExist(err) {
		t.Fatal("installer modified install directory before rejecting Canary")
	}
	again, err := os.ReadFile(rolePath)
	if err != nil || string(again) != string(b) {
		t.Fatal("stored role state modified by blocked migration")
	}
	for _, file := range []string{"server.json", "role.json.new", "MIGRATION-COMPLETE.txt"} {
		if _, err := os.Stat(filepath.Join(dataDir, file)); !os.IsNotExist(err) {
			t.Fatalf("unexpected migration artifact %s", file)
		}
	}
}
