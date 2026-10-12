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

func authReq(method, target, remote string, hdr map[string]string) *http.Request {
	r := httptest.NewRequest(method, "http://127.0.0.1:8787"+target, strings.NewReader("{}"))
	r.Host = "127.0.0.1:8787"
	r.RemoteAddr = remote
	for k, v := range hdr {
		r.Header.Set(k, v)
	}
	return r
}

const (
	testHostToken  = "host-token-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	testAgentToken = "gsa_agent-token-ABCDEFGHIJKLMNOPQRSTUV"
	loopRemote     = "127.0.0.1:50001"
	lanRemote      = "192.168.0.20:50001"
)

func authConfig(scope string) Config {
	return Config{AllowLoopbackNoAuth: true, LoopbackNoAuthScope: scope, APIToken: testHostToken, AgentAPIToken: testAgentToken, Port: 8787}
}

// gate runs the real requireAuth wrapper around a stub handler and returns the status.
func gate(t *testing.T, r *http.Request) int {
	t.Helper()
	rec := httptest.NewRecorder()
	requireAuth(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })(rec, r)
	return rec.Code
}

func TestEffectiveLoopbackScope(t *testing.T) {
	cases := map[string]string{"": "read", "read": "read", "READ": "read", "full": "full", " Full ": "full", "off": "off", "bogus": "read"}
	for in, want := range cases {
		if got := effectiveLoopbackScope(Config{AllowLoopbackNoAuth: true, LoopbackNoAuthScope: in}); got != want {
			t.Errorf("scope %q -> %q want %q", in, got, want)
		}
	}
	if got := effectiveLoopbackScope(Config{AllowLoopbackNoAuth: false, LoopbackNoAuthScope: "full"}); got != "off" {
		t.Errorf("AllowLoopbackNoAuth=false must win, got %q", got)
	}
}

func TestTokenFreeLocalProgramIsReadOnlyByDefault(t *testing.T) {
	withTestConfig(t, authConfig(""))
	allowed := []string{"/api/status", "/api/settings", "/api/v1/snapshot", "/api/v1/servers", "/api/v1/servers/wild",
		"/api/v1/servers/wild/health", "/api/v1/servers/wild/players", "/api/v1/jobs", "/api/v1/jobs/abc", "/api/v4/update/fleet",
		"/api/v4/health", "/api/v4/backups", "/api/v4/network/entry-status", "/api/v4/system"}
	for _, p := range allowed {
		if c := gate(t, authReq("GET", p, loopRemote, nil)); c != http.StatusNoContent {
			t.Errorf("GET %s read-only local: %d", p, c)
		}
	}
	denied := []struct{ m, p string }{
		{"POST", "/api/settings"}, {"POST", "/api/server/action"}, {"POST", "/api/server/command"},
		{"POST", "/api/v1/servers/wild/actions"}, {"POST", "/api/v1/servers/wild/command"},
		{"POST", "/api/v4/server-profile"}, {"POST", "/api/v4/update/self/apply"}, {"POST", "/api/v4/restore"},
		{"GET", "/api/v4/fs"}, {"GET", "/api/log"}, {"GET", "/api/v1/audit"}, {"GET", "/api/v1/devices"},
		{"GET", "/api/v1/pairing/qr"}, {"GET", "/api/v4/pairing/code"}, {"GET", "/api/v1/mobile"}, {"GET", "/api/v1/ws"},
		{"GET", "/api/v4/update/check"}, {"GET", "/api/v1/servers/wild/console"}, {"GET", "/api/v1/jobs/a/b"},
		{"DELETE", "/api/v1/servers/wild"}, {"PUT", "/api/settings"},
	}
	for _, d := range denied {
		if c := gate(t, authReq(d.m, d.p, loopRemote, nil)); c != http.StatusUnauthorized {
			t.Errorf("%s %s token-free local: %d want 401", d.m, d.p, c)
		}
	}
}

func TestReadOnlyDenialPromptsForToken(t *testing.T) {
	withTestConfig(t, authConfig(""))
	rec := httptest.NewRecorder()
	requireAuth(func(w http.ResponseWriter, r *http.Request) {})(rec, authReq("POST", "/api/settings", loopRemote, nil))
	if rec.Code != 401 || !strings.Contains(rec.Header().Get("WWW-Authenticate"), "Bearer") {
		t.Fatalf("want 401 + WWW-Authenticate so dashboards prompt; got %d %q", rec.Code, rec.Header().Get("WWW-Authenticate"))
	}
}

func TestHostTokenAndDeviceKeepFullAccess(t *testing.T) {
	withTestConfig(t, authConfig(""))
	for _, remote := range []string{loopRemote, lanRemote} {
		r := authReq("POST", "/api/settings", remote, map[string]string{"Authorization": "Bearer " + testHostToken})
		if c := gate(t, r); c != http.StatusNoContent {
			t.Errorf("host token from %s: %d", remote, c)
		}
		r = authReq("POST", "/api/settings", remote, map[string]string{"X-GSC-Token": testHostToken})
		if c := gate(t, r); c != http.StatusNoContent {
			t.Errorf("X-GSC-Token from %s: %d", remote, c)
		}
	}
}

func TestAgentTokenIsScopedToDiscordRoutesAndLoopback(t *testing.T) {
	withTestConfig(t, authConfig(""))
	auth := map[string]string{"Authorization": "Bearer " + testAgentToken}
	ok := []struct{ m, p string }{
		{"GET", "/api/v1/servers/wild"}, {"GET", "/api/v1/servers/wild/health"},
		{"POST", "/api/v1/servers/wild/actions"}, {"POST", "/api/v1/servers/playground/command"},
	}
	for _, x := range ok {
		if c := gate(t, authReq(x.m, x.p, loopRemote, auth)); c != http.StatusNoContent {
			t.Errorf("agent %s %s: %d", x.m, x.p, c)
		}
	}
	forbidden := []struct{ m, p string }{
		{"POST", "/api/settings"}, {"GET", "/api/settings"}, {"POST", "/api/v4/server-profile"},
		{"POST", "/api/v4/update/self/apply"}, {"GET", "/api/v4/fs"}, {"POST", "/api/v1/pairing"},
		{"GET", "/api/v1/devices"}, {"POST", "/api/v4/restore"}, {"GET", "/api/v1/servers/wild/actions"},
		{"POST", "/api/v1/servers/wild"}, {"POST", "/api/v1/servers/wild/files"},
	}
	for _, x := range forbidden {
		if c := gate(t, authReq(x.m, x.p, loopRemote, auth)); c != http.StatusForbidden {
			t.Errorf("agent %s %s: %d want 403", x.m, x.p, c)
		}
	}
	// A leaked agent token is useless from the LAN/Tailscale.
	if c := gate(t, authReq("POST", "/api/v1/servers/wild/actions", lanRemote, auth)); c != http.StatusUnauthorized {
		t.Errorf("agent token from LAN: %d want 401", c)
	}
}

func TestUnknownTokenFallsBackToReadOnlyNotFull(t *testing.T) {
	withTestConfig(t, authConfig("full"))
	// Even in legacy "full" mode a WRONG token never escalates beyond the scope;
	// with "full" a token-free/wrong-token loopback call is the legacy principal.
	p, ok := authenticateRequest(authReq("GET", "/api/status", loopRemote, map[string]string{"Authorization": "Bearer stale"}))
	if !ok || p.Kind != principalLocal {
		t.Fatalf("full scope fallback: %v %v", p, ok)
	}
	cfg.LoopbackNoAuthScope = ""
	p, ok = authenticateRequest(authReq("POST", "/api/settings", loopRemote, map[string]string{"Authorization": "Bearer stale"}))
	if !ok || p.Kind != principalLocalReadOnly {
		t.Fatalf("stale token should fall back to read-only: %v %v", p, ok)
	}
	if c := gate(t, authReq("POST", "/api/settings", loopRemote, map[string]string{"Authorization": "Bearer stale"})); c != 401 {
		t.Fatalf("stale token POST: %d", c)
	}
	// From the LAN a wrong token is simply refused.
	if c := gate(t, authReq("GET", "/api/status", lanRemote, map[string]string{"Authorization": "Bearer stale"})); c != 401 {
		t.Fatalf("LAN stale token: %d", c)
	}
}

func TestLegacyFullScopeAndOff(t *testing.T) {
	withTestConfig(t, authConfig("full"))
	if c := gate(t, authReq("POST", "/api/settings", loopRemote, nil)); c != http.StatusNoContent {
		t.Fatalf("explicit full scope must keep legacy behaviour: %d", c)
	}
	// Browser guard still applies in full scope.
	if c := gate(t, authReq("POST", "/api/settings", loopRemote, map[string]string{"Origin": "https://evil.example"})); c != 401 {
		t.Fatalf("cross-site in full scope: %d", c)
	}
	cfg.LoopbackNoAuthScope = "off"
	if c := gate(t, authReq("GET", "/api/status", loopRemote, nil)); c != 401 {
		t.Fatalf("off scope: %d", c)
	}
}

func TestBrowserGuardStillAppliesToReadOnlyScope(t *testing.T) {
	withTestConfig(t, authConfig(""))
	r := authReq("GET", "/api/settings", loopRemote, nil)
	r.Host = "rebind.evil.example:8787" // DNS rebinding read
	if c := gate(t, r); c != 401 {
		t.Fatalf("rebinding read-only: %d", c)
	}
	if c := gate(t, authReq("GET", "/api/settings", loopRemote, map[string]string{"Sec-Fetch-Site": "cross-site"})); c != 401 {
		t.Fatalf("cross-site read-only: %d", c)
	}
}

func TestEnsureAgentGSCTokenProvisionsAndIsIdempotent(t *testing.T) {
	withTestConfig(t, Config{AllowLoopbackNoAuth: true, APIToken: testHostToken, Port: 8787})
	props := filepath.Join(t.TempDir(), "agent.properties")
	orig := "# managed\r\ngsc.enabled=true\r\ngsc.base_url=http://127.0.0.1:8787/api/v1\r\ngsc.token=\r\nsecret=abc\r\n"
	if err := os.WriteFile(props, []byte(orig), 0600); err != nil {
		t.Fatal(err)
	}
	changed, err := ensureAgentGSCToken(props)
	if err != nil || !changed {
		t.Fatalf("first provision: %v %v", changed, err)
	}
	tok := configSnapshot().AgentAPIToken
	if !strings.HasPrefix(tok, "gsa_") || len(tok) < 40 {
		t.Fatalf("weak agent token %q", tok)
	}
	b, _ := os.ReadFile(props)
	text := string(b)
	if propertyValue(text, "gsc.token") != tok || propertyValue(text, "secret") != "abc" || propertyValue(text, "gsc.base_url") == "" {
		t.Fatalf("agent.properties not patched correctly:\n%s", text)
	}
	if strings.Count(text, "gsc.token=") != 1 {
		t.Fatalf("duplicate gsc.token lines:\n%s", text)
	}
	// Persisted in server.json (protected form on Windows) and reloaded.
	disk, _ := os.ReadFile(configPath)
	var raw map[string]any
	_ = json.Unmarshal(disk, &raw)
	if raw["agent_api_token"] == nil || raw["agent_api_token"] == "" {
		t.Fatal("agent_api_token not persisted")
	}
	loaded, err := loadOrCreateConfig(configPath)
	if err != nil || loaded.AgentAPIToken != tok {
		t.Fatalf("reload: %v %q", err, loaded.AgentAPIToken)
	}
	changed, err = ensureAgentGSCToken(props)
	if err != nil || changed {
		t.Fatalf("second call must be a no-op: %v %v", changed, err)
	}
	if configSnapshot().AgentAPIToken != tok {
		t.Fatal("token rotated unexpectedly")
	}
}

func TestSettingsGETNeverExposesTokens(t *testing.T) {
	withTestConfig(t, authConfig(""))
	rec := httptest.NewRecorder()
	requireAuth(apiSettings)(rec, authReq("GET", "/api/settings", loopRemote, nil))
	if rec.Code != 200 {
		t.Fatalf("settings GET %d", rec.Code)
	}
	body := rec.Body.String()
	if strings.Contains(body, testHostToken) || strings.Contains(body, testAgentToken) {
		t.Fatal("settings response leaked a token")
	}
}
