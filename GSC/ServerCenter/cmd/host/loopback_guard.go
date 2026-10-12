package main

import (
	"net"
	"net/http"
	"net/url"
	"strings"
)

// loopbackNoAuthRequestAllowed decides whether a request already arriving
// over a loopback socket may use the legacy AllowLoopbackNoAuth shortcut.
// Cross-site browser requests and DNS-rebinding Host names must use normal
// token/device authentication instead. This is NOT protection against local
// non-browser processes; that requires disabling the shortcut entirely.
func loopbackNoAuthRequestAllowed(r *http.Request) bool {
	if !isLoopbackHostName(r.Host) {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(r.Header.Get("Sec-Fetch-Site"))) {
	case "", "same-origin", "none":
	default:
		return false
	}
	if origin := strings.TrimSpace(r.Header.Get("Origin")); origin != "" {
		return sameLoopbackOrigin(origin, r.Host)
	}
	return true
}

func splitHostMaybePort(hostport string) string {
	h := strings.TrimSpace(hostport)
	if host, _, err := net.SplitHostPort(h); err == nil {
		return host
	}
	return strings.TrimSuffix(strings.TrimPrefix(h, "["), "]")
}

func isLoopbackHostName(hostport string) bool {
	h := strings.ToLower(splitHostMaybePort(hostport))
	if h == "" {
		return false
	}
	if h == "localhost" {
		return true
	}
	ip := net.ParseIP(h)
	return ip != nil && ip.IsLoopback()
}

// sameLoopbackOrigin requires the full origin authority (including port) to
// match the loopback request Host. Sandboxed "null" and arbitrary websites fail.
func sameLoopbackOrigin(origin, reqHost string) bool {
	u, err := url.Parse(origin)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return false
	}
	if !strings.EqualFold(u.Host, strings.TrimSpace(reqHost)) {
		return false
	}
	return isLoopbackHostName(u.Host)
}
