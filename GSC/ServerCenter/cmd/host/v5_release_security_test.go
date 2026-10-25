package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

// This tests the published v5 capabilities without starting a Host service.
// The v4 management routes and external Scheduler-owned proxies are unchanged.
func TestV5ReleaseCapabilitiesFailClosed(t *testing.T) {
	rec := httptest.NewRecorder()
	apiV5ReleaseInfo(rec, httptest.NewRequest(http.MethodGet, "/api/v5/release", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET release status=%d", rec.Code)
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("v5 release response must not be cached")
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
		t.Fatalf("unexpected response content type %q", got)
	}

	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"ok": true,
		"product": "Geumyi Server Center",
		"version": "5.0.0-beta.1",
		"channel": "beta",
		"api_compatible_major": float64(4),
		"product_major": float64(5),
		"gscm_version_unchanged": true,
		"velocity_lifecycle_owner": "windows_task_scheduler",
		"gsc_owns_velocity_processes": false,
		"automatic_stable_promotion": false,
		"stable_release_requires_manual_operator": true,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("v5 capabilities changed unexpectedly: got=%#v want=%#v", got, want)
	}
}

func TestV5ReleaseRemoteAuthAndNetworkGate(t *testing.T) {
	withMobileTestConfig(t, true)
	configMu.Lock()
	cfg.APIToken = "v5-ci-disposable-token"
	cfg.AllowLoopbackNoAuth = true
	configMu.Unlock()

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v5/release", requireAuth(apiV5ReleaseInfo))
	h := securityHeaders(mobileNetworkGuard(mux))

	tests := []struct {
		name, peer, token string
		want              int
	}{
		{"tailnet-ipv4-no-token", "100.64.0.12:4123", "", http.StatusUnauthorized},
		{"tailnet-ipv4-invalid-token", "100.64.0.12:4123", "incorrect", http.StatusUnauthorized},
		{"tailnet-ipv6-no-token", "[fd7a:115c:a1e0::12]:4123", "", http.StatusUnauthorized},
		{"lan-ipv4-no-token", "192.168.10.12:4123", "", http.StatusUnauthorized},
		{"tailnet-ipv4-valid-token", "100.64.0.12:4123", "v5-ci-disposable-token", http.StatusOK},
		{"tailnet-ipv6-valid-token", "[fd7a:115c:a1e0::12]:4123", "v5-ci-disposable-token", http.StatusOK},
		{"public-ip-denied-even-with-token", "8.8.8.8:4123", "v5-ci-disposable-token", http.StatusForbidden},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "http://gsc.test/api/v5/release", nil)
			req.RemoteAddr = tc.peer
			req.Header.Set("X-Forwarded-For", "127.0.0.1")
			req.Header.Set("X-GSC-Actor", "forged-local-admin")
			req.Header.Set("X-GSC-Source", "local")
			if tc.token != "" {
				req.Header.Set("Authorization", "Bearer "+tc.token)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("peer=%s status=%d, want=%d", tc.peer, rec.Code, tc.want)
			}
			if rec.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("all release responses must disable caching")
			}
			if tc.want != http.StatusOK && len(rec.Body.Bytes()) == 0 {
				t.Fatal("denied request did not produce a status response")
			}
		})
	}
}

func TestV5ReleaseRefusesMutationsThroughAuthenticatedRoute(t *testing.T) {
	withMobileTestConfig(t, true)
	configMu.Lock()
	cfg.APIToken = "v5-ci-disposable-token"
	configMu.Unlock()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v5/release", requireAuth(apiV5ReleaseInfo))
	h := securityHeaders(mobileNetworkGuard(mux))

	for _, method := range []string{http.MethodHead, http.MethodOptions, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete} {
		t.Run(method, func(t *testing.T) {
			req := httptest.NewRequest(method, "http://gsc.test/api/v5/release", nil)
			req.RemoteAddr = "100.64.0.12:4123"
			req.Header.Set("Authorization", "Bearer v5-ci-disposable-token")
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("authenticated %s status=%d, want 405", method, rec.Code)
			}
		})
	}
}

func TestV5ReleaseRemoteDisabledRejectsKnownToken(t *testing.T) {
	withMobileTestConfig(t, false)
	configMu.Lock()
	cfg.APIToken = "v5-ci-disposable-token"
	configMu.Unlock()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v5/release", requireAuth(apiV5ReleaseInfo))
	req := httptest.NewRequest(http.MethodGet, "http://gsc.test/api/v5/release", nil)
	req.RemoteAddr = "[fd7a:115c:a1e0::12]:4123"
	req.Header.Set("Authorization", "Bearer v5-ci-disposable-token")
	rec := httptest.NewRecorder()
	securityHeaders(mobileNetworkGuard(mux)).ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("mobile access disabled status=%d, want 403", rec.Code)
	}
}
