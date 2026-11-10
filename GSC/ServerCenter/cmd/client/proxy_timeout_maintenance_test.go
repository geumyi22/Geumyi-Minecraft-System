//go:build windows

package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestMaintenanceProxyRoutesKeepStatusFastAndStageLong(t *testing.T) {
	for _, p := range []string{"/api/v4/update/external/stage", "/api/v4/update/external/status", "/api/v4/backup", "/api/v4/restore", "/api/v4/update/external/apply-proxy"} {
		if clientProxyTransportForPath(p) != clientLongProxyTransport {
			t.Fatalf("long request budget absent for %s", p)
		}
	}
	for _, p := range []string{"/api/status", "/api/health", "/api/settings"} {
		if clientProxyTransportForPath(p) != clientProxyTransport {
			t.Fatalf("ordinary request budget changed for %s", p)
		}
	}
	if clientProxyTransport.ResponseHeaderTimeout != 12*time.Second {
		t.Fatal("ordinary timeout changed")
	}
}
func TestMaintenanceProxySlowStageResponse(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(80 * time.Millisecond)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"live_files_modified":false,"staged":[]}`))
	}))
	defer backend.Close()
	clientConfigMu.Lock()
	oldCfg := cfg
	cfg = ClientConfig{HostURL: backend.URL}
	clientConfigMu.Unlock()
	oldShort, oldLong := clientProxyTransport, clientLongProxyTransport
	clientProxyTransport = oldShort.Clone()
	clientProxyTransport.ResponseHeaderTimeout = 20 * time.Millisecond
	clientLongProxyTransport = oldLong.Clone()
	clientLongProxyTransport.ResponseHeaderTimeout = time.Second
	defer func() {
		clientProxyTransport.CloseIdleConnections()
		clientLongProxyTransport.CloseIdleConnections()
		clientProxyTransport, clientLongProxyTransport = oldShort, oldLong
		clientConfigMu.Lock()
		cfg = oldCfg
		clientConfigMu.Unlock()
	}()
	rec := httptest.NewRecorder()
	proxyAPI(rec, httptest.NewRequest("POST", "http://127.0.0.1:8790/api/v4/update/external/stage", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("stage should survive ordinary timeout: %d %s", rec.Code, rec.Body.String())
	}
}
