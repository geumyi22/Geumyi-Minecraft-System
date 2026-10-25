// Package localsession protects the GSC desktop Client's loopback UI server
// (http://127.0.0.1:8790) which proxies /api/* to the Host WITH the operator's
// saved API token.
//
// Without it, any local program, any other Windows account on the PC, a
// cross-site web page (text/plain "simple" POST) or a DNS-rebinding page could
// use the proxy as an authenticated confused deputy, or read the token from
// /client/config.
//
// Model:
//   - the Client mints a single-use launch code whenever IT opens the dashboard
//     window (tray/menu) and passes it in the URL (?gsc_launch=...);
//   - redeeming the code sets an HttpOnly, SameSite=Strict session cookie bound
//     to this Client process (a new random secret per process start);
//   - every other request must carry that cookie and a loopback Host header for
//     the Client's own port; state-changing requests additionally require a
//     same-origin Origin / Sec-Fetch-Site when present.
//
// Same-user processes are intentionally out of scope: they can already decrypt
// client.json (user-scope DPAPI). The gate removes the token-free path for
// browsers and other accounts.
package localsession

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	CookieName = "gsc_client_session"
	LaunchKey  = "gsc_launch"
	launchTTL  = 2 * time.Minute
	maxPending = 16
)

type Gate struct {
	port    int
	session string
	mu      sync.Mutex
	pending map[string]time.Time
	now     func() time.Time
	// Exempt paths answer without a session (e.g. the second-instance
	// "open a window" signal). They still get Host/Origin checks.
	exempt map[string]bool
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("localsession: crypto/rand failed: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// New creates a gate for the Client UI listening on 127.0.0.1:port.
func New(port int, exemptPaths ...string) *Gate {
	g := &Gate{port: port, session: randomHex(32), pending: map[string]time.Time{}, now: time.Now, exempt: map[string]bool{}}
	for _, p := range exemptPaths {
		g.exempt[p] = true
	}
	return g
}

// NewLaunchCode returns a fresh single-use code (valid for two minutes).
func (g *Gate) NewLaunchCode() string {
	code := randomHex(24)
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	for k, exp := range g.pending {
		if now.After(exp) {
			delete(g.pending, k)
		}
	}
	if len(g.pending) >= maxPending { // bound memory if windows are spammed
		for k := range g.pending {
			delete(g.pending, k)
			break
		}
	}
	g.pending[code] = now.Add(launchTTL)
	return code
}

// LaunchURL builds the URL the Client opens itself. fragment may be "".
func (g *Gate) LaunchURL(fragment string) string {
	u := "http://127.0.0.1:" + strconv.Itoa(g.port) + "/?" + LaunchKey + "=" + g.NewLaunchCode()
	if fragment != "" {
		u += "#" + strings.TrimPrefix(fragment, "#")
	}
	return u
}

func (g *Gate) redeem(code string) bool {
	if code == "" {
		return false
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	for k, exp := range g.pending {
		if subtle.ConstantTimeCompare([]byte(k), []byte(code)) == 1 {
			delete(g.pending, k) // single use, even if expired
			return !now.After(exp)
		}
	}
	return false
}

func (g *Gate) hasSession(r *http.Request) bool {
	c, err := r.Cookie(CookieName)
	if err != nil || c.Value == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(c.Value), []byte(g.session)) == 1
}

// HostAllowed: the Host header must be a loopback name for OUR port, which
// defeats DNS rebinding (the attacker's hostname would be in Host).
func (g *Gate) HostAllowed(hostport string) bool {
	host, port, err := net.SplitHostPort(strings.TrimSpace(hostport))
	if err != nil || port != strconv.Itoa(g.port) {
		return false
	}
	host = strings.ToLower(host)
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func (g *Gate) sameOrigin(r *http.Request) bool {
	switch strings.ToLower(strings.TrimSpace(r.Header.Get("Sec-Fetch-Site"))) {
	case "", "same-origin", "none":
	default:
		return false
	}
	o := strings.TrimSpace(r.Header.Get("Origin"))
	if o == "" {
		return true
	}
	u, err := url.Parse(o)
	if err != nil || u.Scheme != "http" {
		return false
	}
	return strings.EqualFold(u.Host, r.Host) && g.HostAllowed(u.Host)
}

func isRead(m string) bool { return m == http.MethodGet || m == http.MethodHead }

const lockedPage = `<!doctype html><meta charset="utf-8"><title>Geumyi Server Center</title>` +
	`<body style="font-family:sans-serif;padding:2em;background:#111;color:#eee">` +
	`<h2>관리 창을 다시 열어 주세요</h2><p>보안을 위해 이 화면은 Geumyi Server Center 트레이 아이콘에서 연 창에서만 사용할 수 있습니다.</p>` +
	`<p>Open the dashboard from the Geumyi Server Center tray icon.</p></body>`

// Wrap protects next.
func (g *Gate) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if !g.HostAllowed(r.Host) {
			http.Error(w, "invalid host", http.StatusMisdirectedRequest)
			return
		}
		if !isRead(r.Method) && !g.sameOrigin(r) {
			http.Error(w, "cross-origin request refused", http.StatusForbidden)
			return
		}
		if g.exempt[r.URL.Path] {
			next.ServeHTTP(w, r)
			return
		}
		if code := r.URL.Query().Get(LaunchKey); code != "" && r.URL.Path == "/" && isRead(r.Method) {
			if g.redeem(code) {
				http.SetCookie(w, &http.Cookie{Name: CookieName, Value: g.session, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
				// Drop the code from the address bar; the browser keeps the #fragment.
				http.Redirect(w, r, "/", http.StatusSeeOther)
				return
			}
		}
		if !g.hasSession(r) {
			if r.URL.Path == "/" && isRead(r.Method) {
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(lockedPage))
				return
			}
			http.Error(w, "client session required", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// StripForUpstream removes the Client session cookie (and any other cookie)
// before a request is proxied to the Host, so the local secret never leaves
// this PC.
func StripForUpstream(h http.Header) {
	h.Del("Cookie")
}
