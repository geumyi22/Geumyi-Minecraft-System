//go:build windows

package main

import (
	"strings"
	"testing"
)

func TestGSCUpdateHealthRequiresExactTargetVersion(t *testing.T) {
	tests := []struct {
		name string
		body string
		version string
		want bool
	}{
		{"matching candidate", `{"ok":true,"version":"4.3.9-rc.2","service":true,"generation":4}`, "4.3.9-rc.2", true},
		{"old host must fail candidate", `{"ok":true,"version":"4.3.8","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"future host must fail candidate", `{"ok":true,"version":"4.3.9","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"stray http 200 invalid body", "OK", "4.3.9-rc.2", false},
		{"no ok", `{"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"not ok", `{"ok":false,"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"wrong generation", `{"ok":true,"version":"4.3.9-rc.2","generation":3}`, "4.3.9-rc.2", false},
		{"malformed json", `{"ok":true,"version":"4.3.9-rc.2"`, "4.3.9-rc.2", false},
		{"rollback gsc v4 accepted", `{"ok":true,"version":"4.3.8","generation":4}`, "", true},
		{"rollback empty version rejected", `{"ok":true,"version":"","generation":4}`, "", false},
		{"rollback unrelated service rejected", `{"ok":true,"version":"other","generation":2}`, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := gscHealthIsTarget(strings.NewReader(tt.body), tt.version)
			if got != tt.want {
				t.Fatalf("health version %q: got %v, want %v", tt.version, got, tt.want)
			}
		})
	}
}
