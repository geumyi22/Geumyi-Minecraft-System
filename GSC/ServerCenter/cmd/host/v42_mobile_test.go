package main

import (
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func withMobileTestConfig(t *testing.T, enabled bool) {
	t.Helper()
	configMu.Lock()
	oldCfg := cfg
	oldPath := configPath
	cfg = defaultConfig()
	cfg.MobileEnabled = enabled
	cfg.PairingTTLSeconds = 300
	configPath = filepath.Join(t.TempDir(), "server.json")
	configMu.Unlock()
	pairMu.Lock()
	oldPair := pair
	pair = pairingState{}
	pairMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldPath
		configMu.Unlock()
		pairMu.Lock()
		pair = oldPair
		pairMu.Unlock()
	})
}

func TestTrustedPrivateIP(t *testing.T) {
	good := []string{"127.0.0.1", "192.168.1.20", "10.1.2.3", "172.16.4.5", "100.64.1.2", "100.127.255.1", "fd7a:115c:a1e0::1"}
	for _, raw := range good {
		if !isTrustedPrivateIP(net.ParseIP(raw)) {
			t.Fatalf("expected trusted: %s", raw)
		}
	}
	bad := []string{"8.8.8.8", "1.1.1.1", "100.128.0.1"}
	for _, raw := range bad {
		if isTrustedPrivateIP(net.ParseIP(raw)) {
			t.Fatalf("expected untrusted: %s", raw)
		}
	}
}

func TestMobileNetworkGuard(t *testing.T) {
	withMobileTestConfig(t, false)
	h := mobileNetworkGuard(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	r := httptest.NewRequest(http.MethodGet, "http://gsc/api/v1/info", nil)
	r.RemoteAddr = "192.168.1.20:1234"
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatalf("disabled remote code=%d", w.Code)
	}

	r = httptest.NewRequest(http.MethodGet, "http://gsc/api/v1/info", nil)
	r.RemoteAddr = "127.0.0.1:1234"
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusNoContent {
		t.Fatalf("loopback code=%d", w.Code)
	}

	configMu.Lock()
	cfg.MobileEnabled = true
	configMu.Unlock()
	r = httptest.NewRequest(http.MethodGet, "http://gsc/api/v1/info", nil)
	r.RemoteAddr = "100.84.252.113:1234"
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusNoContent {
		t.Fatalf("tailscale code=%d", w.Code)
	}

	r = httptest.NewRequest(http.MethodGet, "http://gsc/api/v1/info", nil)
	r.RemoteAddr = "8.8.8.8:1234"
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatalf("public code=%d", w.Code)
	}
}

func TestPairingFiveMinutesAndOneTimeClaim(t *testing.T) {
	withMobileTestConfig(t, true)
	r := httptest.NewRequest(http.MethodPost, "http://127.0.0.1/api/v1/pairing", bytes.NewBufferString(`{}`))
	r.RemoteAddr = "127.0.0.1:1234"
	w := httptest.NewRecorder()
	apiV1Pairing(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("pair code status=%d body=%s", w.Code, w.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	code, _ := got["code"].(string)
	if len(code) != 8 {
		t.Fatalf("bad code %q", code)
	}
	rem := int(got["remaining_seconds"].(float64))
	if rem != 300 {
		t.Fatalf("ttl=%d", rem)
	}
	pairMu.Lock()
	until := time.Until(pair.Expires)
	pairMu.Unlock()
	if until < 4*time.Minute+55*time.Second || until > 5*time.Minute+2*time.Second {
		t.Fatalf("expiry=%v", until)
	}

	body, _ := json.Marshal(map[string]string{"code": code, "device_id": "phone-1", "name": "GSCM Android"})
	r = httptest.NewRequest(http.MethodPost, "http://gsc/api/v1/pairing/claim", bytes.NewReader(body))
	r.RemoteAddr = "192.168.1.20:2345"
	w = httptest.NewRecorder()
	apiV1PairingClaim(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("claim status=%d body=%s", w.Code, w.Body.String())
	}
	var claim map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &claim)
	tok, _ := claim["device_token"].(string)
	if len(tok) < 20 || !validDeviceToken(tok) {
		t.Fatal("device token invalid")
	}

	r = httptest.NewRequest(http.MethodPost, "http://gsc/api/v1/pairing/claim", bytes.NewReader(body))
	r.RemoteAddr = "192.168.1.20:2345"
	w = httptest.NewRecorder()
	apiV1PairingClaim(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("pairing code must be one-time, got %d", w.Code)
	}
}

func TestPairingQRSVG(t *testing.T) {
	withMobileTestConfig(t, true)
	pairMu.Lock()
	pair = pairingState{Code: "12345678", Expires: time.Now().Add(5 * time.Minute)}
	pairMu.Unlock()
	r := httptest.NewRequest(http.MethodGet, "http://127.0.0.1/api/v1/pairing/qr", nil)
	w := httptest.NewRecorder()
	apiV1PairingQR(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("qr status=%d body=%s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/svg+xml; charset=utf-8" {
		t.Fatalf("unexpected content type %q", ct)
	}
	body := w.Body.String()
	if !bytes.Contains([]byte(body), []byte("<svg")) || !bytes.Contains([]byte(body), []byte("gscm://pair?host=")) {
		t.Fatalf("unexpected qr body")
	}
}
