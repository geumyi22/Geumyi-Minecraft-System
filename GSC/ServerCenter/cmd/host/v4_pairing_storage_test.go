package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// Regression: a different local process can pre-create a fixed .tmp filename
// under some inherited ProgramData directory ACLs. Saving device credentials
// must never touch or follow that predictable placeholder.
func TestSaveDevicesDoesNotTouchPreplantedFixedTempPath(t *testing.T) {
	oldPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldPath }()
	oldFixedTemp := devicesPath() + ".tmp"
	const marker = "DO-NOT-TOUCH-UNTRUSTED-PLACEHOLDER"
	if err := os.WriteFile(oldFixedTemp, []byte(marker), 0600); err != nil {
		t.Fatal(err)
	}
	d := []TrustedDevice{{ID: "fixture", Name: "test", TokenHash: "hash-only", Created: "2000-01-01T00:00:00Z", Role: "admin"}}
	if err := saveDevices(d); err != nil {
		t.Fatalf("saveDevices: %v", err)
	}
	preserved, err := os.ReadFile(oldFixedTemp)
	if err != nil || string(preserved) != marker {
		t.Fatalf("preplanted predictable temp file changed: %v", err)
	}
	b, err := os.ReadFile(devicesPath())
	if err != nil {
		t.Fatal(err)
	}
	var actual []TrustedDevice
	if err := json.Unmarshal(b, &actual); err != nil || len(actual) != 1 || actual[0].ID != "fixture" {
		t.Fatalf("target trusted-device data invalid: %v", err)
	}
	glob, err := filepath.Glob(filepath.Join(v4Root(), ".trusted-devices-*.tmp"))
	if err != nil || len(glob) != 0 {
		t.Fatalf("temporary credentials-file residue: %v / %d", err, len(glob))
	}
}

func TestSaveDevicesReplacesExistingTargetAndPreservesFixedTemp(t *testing.T) {
	oldPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldPath }()
	oldFixedTemp := devicesPath() + ".tmp"
	if err := os.WriteFile(devicesPath(), []byte("[]"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(oldFixedTemp, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := saveDevices([]TrustedDevice{{ID: "replacement", TokenHash: "fixture-hash"}}); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(devicesPath())
	if err != nil {
		t.Fatal(err)
	}
	var got []TrustedDevice
	if err := json.Unmarshal(b, &got); err != nil || len(got) != 1 || got[0].ID != "replacement" {
		t.Fatalf("replacement not persisted: %v", err)
	}
	marker, err := os.ReadFile(oldFixedTemp)
	if err != nil || string(marker) != "keep" {
		t.Fatalf("fixed untrusted temp changed: %v", err)
	}
}
