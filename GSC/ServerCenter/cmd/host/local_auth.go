package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"net/http"
	"path"
	"strings"
)

// Local authentication model (Day 12.5 hardening)
//
// Before: AllowLoopbackNoAuth=true gave EVERY loopback caller the full "local"
// principal. Any local program (any Windows account, any integrity level) could
// change a server's start_command and have the LocalSystem Host execute it.
//
// Now, in order:
//  1. Explicit credentials are checked first:
//     - Host API token          -> "api_token" (full, unchanged)
//     - StatusAgent token       -> "agent" (loopback only, Discord routes only)
//     - trusted device token    -> "device"   (GSCM, unchanged)
//  2. Without a valid credential, the loopback shortcut (still subject to the
//     browser cross-site / DNS-rebinding guard) yields:
//     - scope "read" (DEFAULT): "local-readonly", GET/HEAD on an allowlist of
//     status routes only. Anything else answers 401 so the dashboard prompts
//     for the API token.
//     - scope "full": legacy "local" principal (explicit opt-in only).
//     - scope "off":  no token-free access at all.
const (
	loopbackScopeRead = "read"
	loopbackScopeFull = "full"
	loopbackScopeOff  = "off"

	principalLocal         = "local"
	principalLocalReadOnly = "local-readonly"
	principalAgent         = "agent"
)

func effectiveLoopbackScope(c Config) string {
	if !c.AllowLoopbackNoAuth {
		return loopbackScopeOff
	}
	switch strings.ToLower(strings.TrimSpace(c.LoopbackNoAuthScope)) {
	case loopbackScopeFull:
		return loopbackScopeFull
	case loopbackScopeOff:
		return loopbackScopeOff
	default:
		return loopbackScopeRead
	}
}

func tokenEqual(got, want string) bool {
	if want == "" || got == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// bearerFromRequest keeps the exact pre-existing parsing (TrimPrefix "Bearer",
// then X-GSC-Token) so GSCM, StatusAgent, the dashboards and scripts behave
// identically.
func bearerFromRequest(r *http.Request) string {
	got := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer"))
	if got == "" {
		got = strings.TrimSpace(r.Header.Get("X-GSC-Token"))
	}
	return got
}

// Read-only status routes a token-free local program may still call. These are
// exactly the GET routes used by the repository's read-only operator tools; they
// return no API/device/GitHub/Discord secret. Explicitly excluded: /api/log,
// /api/v1/audit, /api/v1/devices, /api/v1/mobile, pairing, /api/v4/fs,
// /api/v1/ws, /api/v4/update/check (outbound side effect) and every write.
var loopbackReadOnlyRoutes = map[string]bool{
	"/api/health":                    true,
	"/api/status":                    true,
	"/api/settings":                  true,
	"/api/settings/public":           true,
	"/api/v1/info":                   true,
	"/api/v1/snapshot":               true,
	"/api/v1/servers":                true,
	"/api/v1/jobs":                   true,
	"/api/v1/metrics":                true,
	"/api/v4/health":                 true,
	"/api/v4/metrics":                true,
	"/api/v4/system":                 true,
	"/api/v4/backups":                true,
	"/api/v4/backups/trash":          true,
	"/api/v4/inventory":              true,
	"/api/v4/network/entry-status":   true,
	"/api/v4/update/status":          true,
	"/api/v4/update/fleet":           true,
	"/api/v4/update/settings":        true,
	"/api/v4/update/external/status": true,
	"/api/v4/update/self/status":     true,
}

func isReadMethod(m string) bool { return m == http.MethodGet || m == http.MethodHead }

func cleanAPIPath(r *http.Request) string {
	p := path.Clean("/" + strings.TrimPrefix(r.URL.Path, "/"))
	return p
}

// splitV1ServerPath parses /api/v1/servers/{id}[/{sub}].
func splitV1ServerPath(p string) (id, sub string, ok bool) {
	const pre = "/api/v1/servers/"
	if !strings.HasPrefix(p, pre) {
		return "", "", false
	}
	parts := strings.Split(strings.TrimPrefix(p, pre), "/")
	switch {
	case len(parts) == 1 && parts[0] != "":
		return parts[0], "", true
	case len(parts) == 2 && parts[0] != "" && parts[1] != "":
		return parts[0], parts[1], true
	}
	return "", "", false
}

func loopbackReadOnlyPermits(r *http.Request) bool {
	if !isReadMethod(r.Method) {
		return false
	}
	p := cleanAPIPath(r)
	if loopbackReadOnlyRoutes[p] {
		return true
	}
	if _, sub, ok := splitV1ServerPath(p); ok {
		return sub == "" || sub == "health" || sub == "players"
	}
	if strings.HasPrefix(p, "/api/v1/jobs/") {
		return !strings.Contains(strings.TrimPrefix(p, "/api/v1/jobs/"), "/")
	}
	return false
}

// agentPermits is the StatusAgent (Discord) surface, taken from GscClient.java:
// GET servers/{id}, GET servers/{id}/health, POST servers/{id}/actions and
// POST servers/{id}/command. Settings, start_command, paths, updates, backups,
// pairing and devices are NOT reachable with the agent token.
func agentPermits(r *http.Request) bool {
	_, sub, ok := splitV1ServerPath(cleanAPIPath(r))
	if !ok {
		return false
	}
	switch sub {
	case "", "health":
		return isReadMethod(r.Method)
	case "actions", "command":
		return r.Method == http.MethodPost
	}
	return false
}

func principalPermits(p authPrincipal, r *http.Request) bool {
	switch p.Kind {
	case principalLocalReadOnly:
		return loopbackReadOnlyPermits(r)
	case principalAgent:
		return agentPermits(r)
	}
	return true
}

func newAgentAPIToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return "gsa_" + base64.RawURLEncoding.EncodeToString(buf), nil
}

// ensureAgentAPIToken returns the persisted StatusAgent credential, creating
// and saving one (DPAPI-protected like api_token) when it does not exist yet.
func ensureAgentAPIToken() (token string, created bool, err error) {
	c := configSnapshot()
	if t := strings.TrimSpace(c.AgentAPIToken); t != "" {
		return t, false, nil
	}
	t, err := newAgentAPIToken()
	if err != nil {
		return "", false, err
	}
	c.AgentAPIToken = t
	if err := saveHostConfig(c); err != nil {
		return "", false, err
	}
	return t, true, nil
}
