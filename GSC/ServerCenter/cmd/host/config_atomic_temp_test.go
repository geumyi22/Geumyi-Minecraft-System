package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestHostConfigSaveDoesNotTouchPreplantedFixedTemp(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "server.json")
	fixed := target + ".tmp"
	const marker = "DO-NOT-TOUCH-PREPLANTED-TEMP"
	if err := os.WriteFile(fixed, []byte(marker), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("old-config"), 0600); err != nil {
		t.Fatal(err)
	}
	data := []byte(`{"port":8790,"api_token":""}`)
	if err := writeHostConfigSafely(target, data); err != nil {
		t.Fatalf("host config save: %v", err)
	}
	got, err := os.ReadFile(target)
	if err != nil || !bytes.Equal(got, data) {
		t.Fatalf("config not replaced correctly: %v", err)
	}
	fixedGot, err := os.ReadFile(fixed)
	if err != nil || string(fixedGot) != marker {
		t.Fatalf("preplanted fixed temp modified: %v", err)
	}
	if temp, err := filepath.Glob(filepath.Join(dir, ".gsc-config-*.tmp")); err != nil || len(temp) != 0 {
		t.Fatalf("temporary files not cleaned: %v count=%d", err, len(temp))
	}
}

func TestHostConfigRenameFailurePreservesPriorDestinationAndCleansTemp(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "server.json")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(target, "keep.txt")
	if err := os.WriteFile(marker, []byte("untouched"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := writeHostConfigSafely(target, []byte("new")); err == nil {
		t.Fatal("replacing directory with config file must fail")
	}
	got, err := os.ReadFile(marker)
	if err != nil || string(got) != "untouched" {
		t.Fatalf("prior destination was changed on failure: %v", err)
	}
	if temp, err := filepath.Glob(filepath.Join(dir, ".gsc-config-*.tmp")); err != nil || len(temp) != 0 {
		t.Fatalf("failure left temporary files: %v count=%d", err, len(temp))
	}
}

func TestSaveHostConfigUsesRandomTempAndKeepsLegacyTempUntouched(t *testing.T) {
	oldPath, oldCfg := configPath, cfg
	defer func() { configPath, cfg = oldPath, oldCfg }()
	configPath = filepath.Join(t.TempDir(), "server.json")
	fixed := configPath + ".tmp"
	if err := os.WriteFile(fixed, []byte("preplanted"), 0600); err != nil {
		t.Fatal(err)
	}
	next := Config{Port: 8790}
	if err := saveHostConfig(next); err != nil {
		t.Fatalf("saveHostConfig: %v", err)
	}
	b, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	var saved Config
	if err := json.Unmarshal(b, &saved); err != nil || saved.Port != 8790 {
		t.Fatalf("persisted config invalid: %v", err)
	}
	fixedGot, err := os.ReadFile(fixed)
	if err != nil || string(fixedGot) != "preplanted" {
		t.Fatalf("legacy fixed temporary path was modified: %v", err)
	}
}
