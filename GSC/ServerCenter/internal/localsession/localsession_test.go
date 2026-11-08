package localsession

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

const port = 8790

func newGate() (*Gate, http.Handler) {
	g := New(port, "/client/open-window")
	h := g.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" && strings.HasPrefix(r.URL.Path, "/api/") {
			// emulate the proxy: upstream must not see the cookie
			StripForUpstream(r.Header)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK:" + r.URL.Path))
	}))
	return g, h
}

func do(h http.Handler, method, target, host string, hdr map[string]string, cookie *http.Cookie) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://"+host+target, strings.NewReader("{}"))
	r.Host = host
	r.RemoteAddr = "127.0.0.1:55555"
	for k, v := range hdr {
		r.Header.Set(k, v)
	}
	if cookie != nil {
		r.AddCookie(cookie)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func login(t *testing.T, g *Gate, h http.Handler) *http.Cookie {
	t.Helper()
	u, _ := url.Parse(g.LaunchURL("settings"))
	if u.Fragment != "settings" || u.Host != "127.0.0.1:8790" {
		t.Fatalf("launch url %s", u)
	}
	rec := do(h, "GET", "/?"+u.RawQuery, "127.0.0.1:8790", nil, nil)
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/" {
		t.Fatalf("redeem: %d %q", rec.Code, rec.Header().Get("Location"))
	}
	sc := rec.Result().Cookies()
	if len(sc) != 1 || sc[0].Name != CookieName || !sc[0].HttpOnly || sc[0].SameSite != http.SameSiteStrictMode {
		t.Fatalf("cookie attributes: %+v", sc)
	}
	return &http.Cookie{Name: CookieName, Value: sc[0].Value}
}

func TestNoSessionMeansNoProxyNoConfig(t *testing.T) {
	_, h := newGate()
	for _, p := range []string{"/api/settings", "/api/v1/servers/wild/actions", "/client/config", "/client/update/apply"} {
		if rec := do(h, "GET", p, "127.0.0.1:8790", nil, nil); rec.Code != 401 {
			t.Errorf("GET %s without session: %d", p, rec.Code)
		}
	}
	if rec := do(h, "GET", "/", "127.0.0.1:8790", nil, nil); rec.Code != 401 || !strings.Contains(rec.Body.String(), "트레이") {
		t.Errorf("root without session should show the locked page: %d", rec.Code)
	}
}

func TestLaunchCodeIsSingleUseAndExpires(t *testing.T) {
	g, h := newGate()
	u, _ := url.Parse(g.LaunchURL(""))
	if rec := do(h, "GET", "/?"+u.RawQuery, "127.0.0.1:8790", nil, nil); rec.Code != http.StatusSeeOther {
		t.Fatalf("first redeem %d", rec.Code)
	}
	if rec := do(h, "GET", "/?"+u.RawQuery, "127.0.0.1:8790", nil, nil); rec.Code != 401 {
		t.Fatalf("replayed code accepted: %d", rec.Code)
	}
	base := time.Now()
	g.now = func() time.Time { return base }
	u, _ = url.Parse(g.LaunchURL(""))
	g.now = func() time.Time { return base.Add(3 * time.Minute) }
	if rec := do(h, "GET", "/?"+u.RawQuery, "127.0.0.1:8790", nil, nil); rec.Code != 401 {
		t.Fatalf("expired code accepted: %d", rec.Code)
	}
	if rec := do(h, "GET", "/?"+LaunchKey+"=deadbeef", "127.0.0.1:8790", nil, nil); rec.Code != 401 {
		t.Fatalf("forged code accepted: %d", rec.Code)
	}
}

func TestSessionAllowsDashboardTraffic(t *testing.T) {
	g, h := newGate()
	c := login(t, g, h)
	same := map[string]string{"Origin": "http://127.0.0.1:8790", "Sec-Fetch-Site": "same-origin"}
	for _, x := range []struct{ m, p string }{{"GET", "/"}, {"GET", "/client/config"}, {"GET", "/api/status"}, {"POST", "/api/settings"}, {"POST", "/client/config"}} {
		if rec := do(h, x.m, x.p, "127.0.0.1:8790", same, c); rec.Code != 200 {
			t.Errorf("%s %s with session: %d", x.m, x.p, rec.Code)
		}
	}
	// localhost alias is the same machine and port.
	if rec := do(h, "GET", "/api/status", "localhost:8790", nil, c); rec.Code != 200 {
		t.Errorf("localhost alias: %d", rec.Code)
	}
}

func TestCrossSiteAndRebindingAreRefusedEvenWithCookie(t *testing.T) {
	g, h := newGate()
	c := login(t, g, h)
	// text/plain CSRF from another site (a browser would not even attach the
	// SameSite=Strict cookie; refuse regardless).
	if rec := do(h, "POST", "/api/settings", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example", "Sec-Fetch-Site": "cross-site", "Content-Type": "text/plain"}, c); rec.Code != 403 {
		t.Errorf("cross-site POST: %d", rec.Code)
	}
	if rec := do(h, "POST", "/client/config", "127.0.0.1:8790", map[string]string{"Origin": "http://127.0.0.1:3000"}, c); rec.Code != 403 {
		t.Errorf("other local origin POST: %d", rec.Code)
	}
	if rec := do(h, "POST", "/api/settings", "127.0.0.1:8790", map[string]string{"Origin": "null"}, c); rec.Code != 403 {
		t.Errorf("null origin POST: %d", rec.Code)
	}
	for _, host := range []string{"rebind.evil.example:8790", "127.0.0.1:8787", "127.0.0.1", "192.168.0.5:8790"} {
		if rec := do(h, "GET", "/client/config", host, nil, c); rec.Code != http.StatusMisdirectedRequest {
			t.Errorf("Host %q: %d", host, rec.Code)
		}
	}
}

func TestSessionIsPerProcess(t *testing.T) {
	g1, h1 := newGate()
	c := login(t, g1, h1)
	_, h2 := newGate() // Client restarted: old cookie must not work
	if rec := do(h2, "GET", "/api/status", "127.0.0.1:8790", nil, c); rec.Code != 401 {
		t.Fatalf("stale cookie from previous process accepted: %d", rec.Code)
	}
}

func TestExemptOpenWindowSignal(t *testing.T) {
	_, h := newGate()
	// Second Client instance (local program, no Origin) may ask for a window.
	if rec := do(h, "POST", "/client/open-window", "127.0.0.1:8790", nil, nil); rec.Code != 200 {
		t.Fatalf("open-window from local program: %d", rec.Code)
	}
	// A web page cannot spam it.
	if rec := do(h, "POST", "/client/open-window", "127.0.0.1:8790", map[string]string{"Origin": "https://evil.example"}, nil); rec.Code != 403 {
		t.Fatalf("open-window cross-site: %d", rec.Code)
	}
	if rec := do(h, "POST", "/client/open-window", "evil.example:8790", nil, nil); rec.Code != http.StatusMisdirectedRequest {
		t.Fatalf("open-window rebinding: %d", rec.Code)
	}
}

func TestPendingCodesAreBounded(t *testing.T) {
	g := New(port)
	for i := 0; i < 100; i++ {
		g.NewLaunchCode()
	}
	if len(g.pending) > maxPending {
		t.Fatalf("pending codes unbounded: %d", len(g.pending))
	}
}

func TestStripForUpstream(t *testing.T) {
	h := http.Header{}
	h.Set("Cookie", CookieName+"=secret")
	h.Set("Authorization", "Bearer t")
	StripForUpstream(h)
	if h.Get("Cookie") != "" || h.Get("Authorization") != "Bearer t" {
		t.Fatalf("strip: %v", h)
	}
}
