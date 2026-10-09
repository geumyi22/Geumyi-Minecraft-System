package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDay12ManagedJavaBindGuard(t *testing.T) {
	tests := []struct {
		name       string
		id         string
		port       int
		properties string
		wantStatus string
		wantApply  bool
	}{
		{name: "wild loopback IPv4", id: "wild", port: 25570, properties: "server-ip=127.0.0.1\nserver-port=25570\n", wantStatus: "ok", wantApply: true},
		{name: "lobby loopback IPv6", id: "lobby", port: 25573, properties: "server-ip=::1\nserver-port=25573\n", wantStatus: "ok", wantApply: true},
		{name: "other alternate IPv4 loopback", id: "other", port: 25572, properties: "server-ip=127.0.0.2\n", wantStatus: "ok", wantApply: true},
		{name: "wild wildcard", id: "wild", port: 25570, properties: "server-ip=0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "wild empty default", id: "wild", port: 25570, properties: "server-ip=\n", wantStatus: "fail", wantApply: true},
		{name: "wild missing key", id: "wild", port: 25570, properties: "server-port=25570\n", wantStatus: "fail", wantApply: true},
		{name: "wild public IPv4", id: "wild", port: 25570, properties: "server-ip=192.0.2.15\n", wantStatus: "fail", wantApply: true},
		{name: "wild IPv6 wildcard", id: "wild", port: 25570, properties: "server-ip=::\n", wantStatus: "fail", wantApply: true},
		{name: "wild malformed", id: "wild", port: 25570, properties: "server-ip=not_an_ip\n", wantStatus: "fail", wantApply: true},
		{name: "legacy wild port excluded", id: "wild", port: 25565, properties: "server-ip=\n", wantStatus: "", wantApply: false},
		{name: "unmanaged profile excluded", id: "experimental", port: 25570, properties: "server-ip=\n", wantStatus: "", wantApply: false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte(tc.properties), 0600); err != nil {
				t.Fatal(err)
			}
			got, message, apply := day12ManagedJavaBindGuard(ServerConfig{ID: tc.id, JavaPort: tc.port}, dir)
			if got != tc.wantStatus || apply != tc.wantApply {
				t.Fatalf("status=%q applicable=%v; want status=%q applicable=%v", got, apply, tc.wantStatus, tc.wantApply)
			}
			if tc.wantApply && !strings.Contains(message, "루프백") {
				t.Fatalf("security guard report is missing loopback context: %q", message)
			}
		})
	}
}

func TestDay12ManagedJavaBindGuardMissingProperties(t *testing.T) {
	got, _, applicable := day12ManagedJavaBindGuard(ServerConfig{ID: "playground", JavaPort: 25571}, t.TempDir())
	if got != "fail" || !applicable {
		t.Fatalf("missing server.properties must fail closed; got %q applicable=%v", got, applicable)
	}
}
