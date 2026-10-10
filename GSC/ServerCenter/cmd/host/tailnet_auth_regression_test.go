package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// Regression for the Day 12.10 observed real SubPC overlay TCP result:
// 8787 was reachable over both Tailscale address families. TCP reachability
// must never be confused with permission to read or control the Host API.
// These tests run in disposable Go test fixtures; no live host is contacted.
func TestTailnetRemoteAuthMandatoryForGSCProtectedRoutes(t *testing.T) {
	withMobileTestConfig(t, true)
	configMu.Lock()
	cfg.APIToken = "disposable-ci-token-only"
	cfg.AllowLoopbackNoAuth = true
	configMu.Unlock()

	mux := http.NewServeMux()
	mux.HandleFunc("/api/status", requireAuth(apiStatus))
	mux.HandleFunc("/api/settings", requireAuth(apiSettings))
	registerControlAPIRoutes(mux)
	registerV4Routes(mux)
	h := mobileNetworkGuard(mux)

	protected := []string{
		"/api/status",
		"/api/settings",
		"/api/v1/info",
		"/api/v1/snapshot",
		"/api/v1/servers",
		"/api/v1/jobs",
		"/api/v1/devices",
		"/api/v1/backups",
		"/api/v4/health",
		"/api/v4/network/entry-status",
	}
	remotePeers := []string{
		"100.64.0.10:43001",
		"[fd7a:115c:a1e0::1234]:43001",
	}
	for _, peer := range remotePeers {
		for _, route := range protected {
			for _, header := range []string{"", "Bearer incorrect-token"} {
				t.Run(peer+"|"+route+"|"+header, func(t *testing.T) {
					request := httptest.NewRequest(http.MethodGet, "http://gsc.test"+route, nil)
					request.RemoteAddr = peer
					if header != "" {
						request.Header.Set("Authorization", header)
					}
					// Untrusted X-Forwarded-For or delegated actor headers may not
					// turn a remote tailnet peer into a loopback principal.
					request.Header.Set("X-Forwarded-For", "127.0.0.1")
					request.Header.Set("X-GSC-Actor", "forged-local-admin")
					request.Header.Set("X-GSC-Source", "local")
					recorder := httptest.NewRecorder()
					h.ServeHTTP(recorder, request)
					if recorder.Code != http.StatusUnauthorized {
						t.Fatalf("remote=%q route=%q header=%q status=%d, want 401", peer, route, header, recorder.Code)
					}
				})
			}
		}
	}
}

func TestTailnetMobileAccessDisabledBlocksRemoteBeforeAuth(t *testing.T) {
	withMobileTestConfig(t, false)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/info", requireAuth(apiV1Info))
	h := mobileNetworkGuard(mux)
	for _, peer := range []string{"100.64.0.10:54321", "[fd7a:115c:a1e0::1234]:54321"} {
		request := httptest.NewRequest(http.MethodGet, "http://gsc.test/api/v1/info", nil)
		request.RemoteAddr = peer
		recorder := httptest.NewRecorder()
		h.ServeHTTP(recorder, request)
		if recorder.Code != http.StatusForbidden {
			t.Fatalf("mobile disabled, peer=%q status=%d, want 403", peer, recorder.Code)
		}
	}
}
