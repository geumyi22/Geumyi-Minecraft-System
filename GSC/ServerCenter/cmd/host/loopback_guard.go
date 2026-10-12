package main

import (
	"net"
	"net/http"
	"net/url"
	"strings"
)

// loopbackNoAuthRequestAllowed decides whether a request that already arrived
// over a loopback socket may use AllowLoopbackNoAuth.
//
// Threat: any web page visited in a browser on the server PC can send
// requests to http://127.0.0.1:<port>. "Simple" cross-origin POSTs (for example
// Content-Type text/plain) need no CORS preflight and the JSON handlers decode
// the body regardless of Content-Type, so /api/settings (start_command, path)
// and control routes were reachable without any credential. DNS rebinding
// additionally lets an attacker page read responses.
//
// Legitimate local callers are unaffected:
//   - StatusAgent / scripts: Java HttpClient and PowerShell send no Origin and
//     no Sec-Fetch-* headers and address a loopback literal (Host 127.0.0.1:port).
//   - The Host dashboard served from the same origin: Origin equals Host and
//     Sec-Fetch-Site is "same-origin" (or "none" for typed navigations).
//
// A request rejected here is not refused outright: it continues to token or
// trusted-device authentication, so a dashboard holding a token still works.
func loopbackNoAuthRequestAllowed(r *http.Request) bool {
	if !isLoopbackHostName(r.Host) {
		return false // DNS rebinding: Host carries the attacker's hostname
	}
	switch strings.ToLower(strings.TrimSpace(r.Header.Get("Sec-Fetch-Site"))) {
	case "", "same-origin", "none":
	default:
		return false // cross-site or same-site (another local web app) browser request
	}
	if o := strings.TrimSpace(r.Header.Get("Origin")); o != "" {
		return sameLoopbackOrigin(o, r.Host)
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

// sameLoopbackOrigin accepts only an http(s) Origin whose authority is exactly
// the request Host and is itself a loopback name. "null" and other ports fail.
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
