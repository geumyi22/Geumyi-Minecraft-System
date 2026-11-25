//go:build windows

package main

import (
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf16"
)

func TestOperatingModeUpgradePreflight(t *testing.T) {
	path := filepath.Join(t.TempDir(), "current.json")
	if err := checkOperatingModeJournal(path, true, true); err != nil {
		t.Fatal(err)
	}
	enc := func(s string) string {
		units := utf16.Encode([]rune(s))
		b := make([]byte, 2*len(units))
		for i, u := range units {
			binary.LittleEndian.PutUint16(b[2*i:], u)
		}
		return base64.StdEncoding.EncodeToString(b)
	}
	runID := strings.Join([]string{enc("HKCU"), enc("64"), enc("Run"), enc("Geumyi Server Center"), enc("physical key")}, "|")
	type entry struct{ Kind, Id string }
	for _, tc := range []struct {
		name, pending       string
		owned               []entry
		full, legacy, block bool
	}{
		{"completed restore", "", []entry{}, true, true, false},
		{"pending recovery", "apply", []entry{}, true, true, true},
		{"server role Host service", "", []entry{{"Service", hostServiceName}}, true, true, true},
		{"combined role Host task", "", []entry{{"Task", `\` + hostTaskName}}, true, true, true},
		{"client role replaces Run", "", []entry{{"Run", runID}}, true, false, true},
		{"server helper leaves Run", "", []entry{{"Run", runID}}, false, false, false},
		{"server helper restarts Host", "", []entry{{"Service", hostServiceName}}, false, false, true},
		{"unrelated startup shortcut", "", []entry{{"Startup", "test"}}, true, true, false},
		{"legacy task migration", "", []entry{{"Task", `\MC Web Manager`}}, true, true, true},
		{"client only leaves legacy task", "", []entry{{"Task", `\MC Web Manager`}}, true, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b, _ := json.Marshal(map[string]any{"Schema": 3, "Pending": tc.pending, "Owned": tc.owned})
			if err := os.WriteFile(path, b, 0600); err != nil {
				t.Fatal(err)
			}
			if block := checkOperatingModeJournal(path, tc.full, tc.legacy) != nil; block != tc.block {
				t.Fatalf("blocked=%v", block)
			}
		})
	}
	if err := os.WriteFile(path, []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	if checkOperatingModeJournal(path, true, true) == nil {
		t.Fatal("invalid journal accepted")
	}
}

func TestOperatingModeInstallerRetainsExistingSibling(t *testing.T) {
	if os.Getenv("GSC5_REAL_PAYLOAD_TEST") != "1" {
		t.Skip("requires release build")
	}
	dir := t.TempDir()
	dataDir := t.TempDir()
	target := filepath.Join(dir, operatingModeName)
	if err := os.WriteFile(target, []byte("previous release"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := installOperatingMode(dir, dataDir); err != nil {
		t.Fatal(err)
	}
	candidate, original, err := modePayloadFor(target)
	if err != nil || string(candidate) != string(original) {
		t.Fatal("installed bytes mismatch")
	}
	files, err := filepath.Glob(filepath.Join(dataDir, "Backups", "OperatingMode", "*.bak"))
	if err != nil || len(files) != 1 {
		t.Fatal("expected preserved standalone sibling")
	}
	saved, err := os.ReadFile(files[0])
	if err != nil || string(saved) != "previous release" {
		t.Fatal("backup mismatch")
	}
	if err := installOperatingMode(dir, dataDir); err != nil {
		t.Fatal(err)
	}
}
