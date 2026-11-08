package main

import (
	"net/http/httptest"
	"testing"
)

func TestHostBrowserOriginBoundary(t *testing.T) {
	configMu.Lock()
	old := cfg
	cfg.Port = 8787
	configMu.Unlock()
	defer func() { configMu.Lock(); cfg = old; configMu.Unlock() }()
	for _, tc := range []struct {
		name, origin, site, host, peer string
		allowed                        bool
	}{
		{"native", "", "", "127.0.0.1:8787", "127.0.0.1:1234", true},
		{"client_ui", "http://127.0.0.1:8790", "same-site", "127.0.0.1:8787", "127.0.0.1:1234", true},
		{"host_ui", "http://localhost:8787", "same-origin", "localhost:8787", "127.0.0.1:1234", true},
		{"other_site", "https://evil.invalid", "cross-site", "127.0.0.1:8787", "127.0.0.1:1234", false},
		{"untrusted_loopback_port", "http://127.0.0.1:4567", "same-site", "127.0.0.1:8787", "127.0.0.1:1234", false},
		{"null_origin", "null", "", "127.0.0.1:8787", "127.0.0.1:1234", false},
		{"rebinding_get", "", "same-origin", "evil.invalid:8787", "127.0.0.1:1234", false},
		{"rebinding_post", "http://evil.invalid:8787", "same-origin", "evil.invalid:8787", "127.0.0.1:1234", false},
		{"remote_same_origin", "http://server:8787", "same-origin", "server:8787", "192.168.1.5:1234", true},
		{"remote_cross_origin", "https://evil.invalid", "cross-site", "server:8787", "192.168.1.5:1234", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://127.0.0.1:8787/api/status", nil)
			r.RemoteAddr = tc.peer
			r.Host = tc.host
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("Sec-Fetch-Site", tc.site)
			if got := hostBrowserRequestAllowed(r); got != tc.allowed {
				t.Fatalf("got %v want %v", got, tc.allowed)
			}
		})
	}
}

func TestRemoteClientProxyOriginKeepsValidToken(t *testing.T) {
	configMu.Lock()
	old := cfg
	cfg.Port = 8787
	cfg.APIToken = "disposable-test-only"
	cfg.AllowLoopbackNoAuth = true
	configMu.Unlock()
	defer func() { configMu.Lock(); cfg = old; configMu.Unlock() }()
	for _, valid := range []bool{false, true} {
		r := httptest.NewRequest("GET", "http://server:8787/api/status", nil)
		r.RemoteAddr = "192.168.1.5:1234"
		r.Host = "server:8787"
		r.Header.Set("Origin", "http://127.0.0.1:8790")
		r.Header.Set("Sec-Fetch-Site", "same-origin")
		token := "wrong"
		if valid {
			token = "disposable-test-only"
		}
		r.Header.Set("Authorization", "Bearer "+token)
		if got := hostBrowserRequestAllowed(r); got != valid {
			t.Fatalf("valid=%v got=%v", valid, got)
		}
	}
}
