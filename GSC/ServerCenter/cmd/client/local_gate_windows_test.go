//go:build windows

package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"geumyi/servercenter/internal/localsession"
)

// The proxy must forward the saved Host token but never the local session cookie.
func TestProxyStripsSessionCookieAndAddsToken(t *testing.T) {
	var gotCookie, gotAuth, gotHost string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotCookie, gotAuth, gotHost = r.Header.Get("Cookie"), r.Header.Get("Authorization"), r.Host
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()
	clientConfigMu.Lock()
	old := cfg
	cfg = ClientConfig{HostURL: upstream.URL, Token: "saved-host-token"}
	clientConfigMu.Unlock()
	defer func() { clientConfigMu.Lock(); cfg = old; clientConfigMu.Unlock() }()

	r := httptest.NewRequest("GET", "http://127.0.0.1:8790/api/status", nil)
	r.Header.Set("Cookie", localsession.CookieName+"=local-secret; other=x")
	rec := httptest.NewRecorder()
	proxyAPI(rec, r)
	if rec.Code != 200 {
		t.Fatalf("proxy status %d", rec.Code)
	}
	if gotCookie != "" {
		t.Fatalf("session cookie leaked upstream: %q", gotCookie)
	}
	if gotAuth != "Bearer saved-host-token" {
		t.Fatalf("token not attached: %q", gotAuth)
	}
	if !strings.HasPrefix(upstream.URL, "http://"+gotHost) {
		t.Fatalf("upstream Host header %q", gotHost)
	}
}

func TestGateProtectsClientConfigAndProxy(t *testing.T) {
	g := localsession.New(localPort, "/client/open-window")
	mux := http.NewServeMux()
	mux.HandleFunc("/client/config", clientConfigAPI)
	mux.HandleFunc("/client/open-window", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })
	h := g.Wrap(mux)
	r := httptest.NewRequest("GET", "http://127.0.0.1:8790/client/config", nil)
	r.Host = "127.0.0.1:8790"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusUnauthorized || strings.Contains(rec.Body.String(), "token") && strings.Contains(rec.Body.String(), "host_url") {
		t.Fatalf("client config readable without session: %d %s", rec.Code, rec.Body.String())
	}
	r = httptest.NewRequest("POST", "http://127.0.0.1:8790/client/open-window", strings.NewReader("{}"))
	r.Host = "127.0.0.1:8790"
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("open-window signal: %d", rec.Code)
	}
}

func TestClientOpenWindowAPIRequiresPost(t *testing.T) {
	rec := httptest.NewRecorder()
	clientOpenWindowAPI(rec, httptest.NewRequest("GET", "http://127.0.0.1:8790/client/open-window", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET open-window: %d", rec.Code)
	}
}
