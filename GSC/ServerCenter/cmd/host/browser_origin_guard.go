package main

import (
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// Protect loopback's no-auth exception without breaking authenticated native
// clients and the remote Client proxy. This is additional to requireAuth.
func hostBrowserRequestAllowed(r *http.Request) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	site := r.Header.Get("Sec-Fetch-Site")
	if !isLoopbackRemote(r.RemoteAddr) && (r.Header.Get("Authorization") != "" || r.Header.Get("X-GSC-Token") != "") {
		if _, ok := authenticateRequest(r); ok {
			return true
		}
	}
	if strings.EqualFold(site, "cross-site") {
		return false
	}
	if origin == "" {
		if site != "" && isLoopbackRemote(r.RemoteAddr) {
			u, e := url.Parse("http://" + r.Host)
			if e != nil || u.User != nil || u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
				return false
			}
			ip := net.ParseIP(u.Hostname())
			return (strings.EqualFold(u.Hostname(), "localhost") || (ip != nil && ip.IsLoopback())) && u.Port() == strconv.Itoa(configSnapshot().Port)
		}
		return true
	}
	u, e := url.Parse(origin)
	if e != nil || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return false
	}
	if isLoopbackRemote(r.RemoteAddr) {
		ip := net.ParseIP(u.Hostname())
		return (strings.EqualFold(u.Hostname(), "localhost") || (ip != nil && ip.IsLoopback())) && (u.Port() == strconv.Itoa(configSnapshot().Port) || u.Port() == "8790")
	}
	return strings.EqualFold(u.Host, r.Host)
}
