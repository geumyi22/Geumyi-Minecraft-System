//go:build windows

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestSelfUpdateReportLeavesPreplantedFixedTempUntouched(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "gsc-self-update-last.json")
	fixed := target + ".tmp"
	if err := os.WriteFile(target, []byte(`{"status":"before"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fixed, []byte("preplanted"), 0600); err != nil {
		t.Fatal(err)
	}
	writeSelfUpdateReportAt(target, selfUpdateReport{Schema: 1, TargetVersion: "test", Status: "after"})
	b, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	var got selfUpdateReport
	if err := json.Unmarshal(b, &got); err != nil || got.Status != "after" {
		t.Fatalf("updated report missing or invalid: %v", err)
	}
	stale, err := os.ReadFile(fixed)
	if err != nil || string(stale) != "preplanted" {
		t.Fatalf("fixed temp was touched: %v", err)
	}
	if extra, err := filepath.Glob(filepath.Join(dir, ".gsc-update-report-*.tmp")); err != nil || len(extra) != 0 {
		t.Fatalf("temporary report residue: %v count=%d", err, len(extra))
	}
}

func TestSelfUpdateReportRenameFailureLeavesPriorDestination(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "gsc-self-update-last.json")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(target, "keep.txt")
	if err := os.WriteFile(marker, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	writeSelfUpdateReportAt(target, selfUpdateReport{Schema: 1, Status: "must-not-replace-directory"})
	b, err := os.ReadFile(marker)
	if err != nil || string(b) != "keep" {
		t.Fatalf("prior destination changed: %v", err)
	}
	if extra, err := filepath.Glob(filepath.Join(dir, ".gsc-update-report-*.tmp")); err != nil || len(extra) != 0 {
		t.Fatalf("rename failure left temporary report: %v count=%d", err, len(extra))
	}
}
