//go:build windows

package main

import (
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

func localClientAuthority(raw string) bool {
	u, e := url.Parse("http://" + raw)
	if e != nil || u.User != nil || u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return false
	}
	ip := net.ParseIP(u.Hostname())
	return (strings.EqualFold(u.Hostname(), "localhost") || (ip != nil && ip.IsLoopback())) && u.Port() == strconv.Itoa(localPort)
}
func guardClientBrowserRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		peer, _, e := net.SplitHostPort(r.RemoteAddr)
		ip := net.ParseIP(peer)
		if e != nil || ip == nil || !ip.IsLoopback() || !localClientAuthority(r.Host) || strings.EqualFold(r.Header.Get("Sec-Fetch-Site"), "cross-site") {
			http.Error(w, "Untrusted browser or client origin", http.StatusForbidden)
			return
		}
		if o := strings.TrimSpace(r.Header.Get("Origin")); o != "" {
			u, e := url.Parse(o)
			if e != nil || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Path != "" || u.RawQuery != "" || u.Fragment != "" || !localClientAuthority(u.Host) {
				http.Error(w, "Untrusted browser origin", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
