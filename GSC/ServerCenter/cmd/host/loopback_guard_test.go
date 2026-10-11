package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func loopbackReq(method, host string, hdr map[string]string, body string) *http.Request {
	r := httptest.NewRequest(method, "http://"+host+"/api/settings", strings.NewReader(body))
	r.Host = host
	r.RemoteAddr = "127.0.0.1:53111"
	for k, v := range hdr {
		r.Header.Set(k, v)
	}
	return r
}

func TestLoopbackNoAuthGuardMatrix(t *testing.T) {
	cases := []struct {
		name string
		host string
		hdr  map[string]string
		want bool
	}{
		{"statusagent-no-origin", "127.0.0.1:8790", nil, true},
		{"ipv6-loopback-literal", "[::1]:8790", nil, true},
		{"localhost-name", "localhost:8790", nil, true},
		{"dashboard-same-origin", "127.0.0.1:8790", map[string]string{"Origin": "http://127.0.0.1:8790", "Sec-Fetch-Site": "same-origin"}, true},
		{"typed-navigation", "127.0.0.1:8790", map[string]string{"Sec-Fetch-Site": "none"}, true},
		{"csrf-cross-site-origin", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example", "Sec-Fetch-Site": "cross-site"}, false},
		{"csrf-origin-only-old-browser", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example"}, false},
		{"img-get-cross-site-no-origin", "127.0.0.1:8790", map[string]string{"Sec-Fetch-Site": "cross-site"}, false},
		{"other-local-web-app-same-site", "127.0.0.1:8790", map[string]string{"Origin": "http://127.0.0.1:3000", "Sec-Fetch-Site": "same-site"}, false},
		{"other-port-origin-without-fetch-metadata", "127.0.0.1:8790", map[string]string{"Origin": "http://127.0.0.1:3000"}, false},
		{"sandboxed-null-origin", "127.0.0.1:8790", map[string]string{"Origin": "null"}, false},
		{"dns-rebinding-host", "rebind.evil.example:8790", nil, false},
		{"dns-rebinding-host-and-origin", "rebind.evil.example:8790", map[string]string{"Origin": "http://rebind.evil.example:8790", "Sec-Fetch-Site": "same-origin"}, false},
		{"empty-host", "", nil, false},
	}
	for _, tc := range cases {
		r := loopbackReq(http.MethodPost, tc.host, tc.hdr, "")
		r.Host = tc.host
		if got := loopbackNoAuthRequestAllowed(r); got != tc.want {
			t.Errorf("%s: got %v want %v", tc.name, got, tc.want)
		}
	}
}

func withTestConfig(t *testing.T, c Config) {
	t.Helper()
	oldPath, oldCfg := configPath, cfg
	t.Cleanup(func() { configPath, cfg = oldPath, oldCfg })
	configPath = filepath.Join(t.TempDir(), "server.json")
	cfg = c
}

func TestAuthenticateRequestLoopbackShortcutAndTokenFallback(t *testing.T) {
	withTestConfig(t, Config{AllowLoopbackNoAuth: true, APIToken: "host-token-123"})
	// Local program: token-free shortcut still works.
	if p, ok := authenticateRequest(loopbackReq("GET", "127.0.0.1:8790", nil, "")); !ok || p.Kind != "local" {
		t.Fatalf("local program lost loopback access: %v %v", p, ok)
	}
	// Cross-site browser request without a token: refused.
	if _, ok := authenticateRequest(loopbackReq("POST", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example"}, "")); ok {
		t.Fatal("cross-site browser request authenticated without token")
	}
	// Same cross-site request carrying the real token still authenticates as the token principal.
	p, ok := authenticateRequest(loopbackReq("POST", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example", "Authorization": "Bearer host-token-123"}, ""))
	if !ok || p.Kind != "api_token" {
		t.Fatalf("token fallback broken: %v %v", p, ok)
	}
	// Remote client without token: unchanged (refused).
	r := loopbackReq("GET", "192.168.0.10:8790", nil, "")
	r.RemoteAddr = "192.168.0.20:40000"
	if _, ok := authenticateRequest(r); ok {
		t.Fatal("remote request authenticated without token")
	}
	// Shortcut disabled: loopback needs a token.
	cfg.AllowLoopbackNoAuth = false
	if _, ok := authenticateRequest(loopbackReq("GET", "127.0.0.1:8790", nil, "")); ok {
		t.Fatal("loopback authenticated with AllowLoopbackNoAuth=false and no token")
	}
}

// End-to-end regression for the browser CSRF path: a text/plain "simple" POST
// from another site must not change start_command, while the same request from
// a local program (no Origin) keeps working.
func TestCrossSiteSimplePostCannotChangeStartCommand(t *testing.T) {
	withTestConfig(t, Config{
		AllowLoopbackNoAuth: true, APIToken: "host-token-123", Port: 8790,
		Servers: []ServerConfig{{ID: "wild", Name: "wild", StartCommand: "start.bat", JavaPort: 25565}},
	})
	if err := os.WriteFile(configPath, []byte(`{"original":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	h := requireAuth(apiSettings)
	body := `{"servers":[{"id":"wild","start_command":"powershell -enc AAAA"}]}`

	attack := loopbackReq("POST", "127.0.0.1:8790", map[string]string{
		"Origin": "https://evil.example", "Sec-Fetch-Site": "cross-site", "Content-Type": "text/plain;charset=UTF-8",
	}, body)
	rec := httptest.NewRecorder()
	h(rec, attack)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("cross-site POST status %d, want 401", rec.Code)
	}
	if got := configSnapshot().Servers[0].StartCommand; got != "start.bat" {
		t.Fatalf("start_command changed by cross-site request: %q", got)
	}
	if b, _ := os.ReadFile(configPath); string(b) != `{"original":true}` {
		t.Fatalf("config file rewritten by cross-site request: %s", b)
	}

	local := loopbackReq("POST", "127.0.0.1:8790", map[string]string{"Content-Type": "application/json"},
		`{"servers":[{"id":"wild","start_command":"run.bat"}]}`)
	rec = httptest.NewRecorder()
	h(rec, local)
	if rec.Code != http.StatusOK {
		t.Fatalf("local program POST status %d: %s", rec.Code, rec.Body.String())
	}
	var saved Config
	b, _ := os.ReadFile(configPath)
	if err := json.Unmarshal(b, &saved); err != nil || len(saved.Servers) == 0 || saved.Servers[0].StartCommand != "run.bat" {
		t.Fatalf("local settings update not persisted: %v %s", err, b)
	}
}
