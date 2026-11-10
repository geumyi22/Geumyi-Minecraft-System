//go:build windows

package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLocalClientBrowserBoundary(t *testing.T) {
	handler := guardClientBrowserRequests(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	for _, tc := range []struct {
		name, host, origin, site, peer string
		code                           int
	}{
		{"native", "127.0.0.1:8790", "", "", "127.0.0.1:1234", 204},
		{"ui", "127.0.0.1:8790", "http://127.0.0.1:8790", "same-origin", "127.0.0.1:1234", 204},
		{"localhost", "localhost:8790", "http://localhost:8790", "same-origin", "127.0.0.1:1234", 204},
		{"rebinding", "evil.invalid:8790", "http://evil.invalid:8790", "same-origin", "127.0.0.1:1234", 403},
		{"foreign_origin", "127.0.0.1:8790", "https://evil.invalid", "cross-site", "127.0.0.1:1234", 403},
		{"cross_site_image", "127.0.0.1:8790", "", "cross-site", "127.0.0.1:1234", 403},
		{"null", "127.0.0.1:8790", "null", "", "127.0.0.1:1234", 403},
		{"remote_peer", "127.0.0.1:8790", "", "", "192.168.1.5:1234", 403},
		{"userinfo", "evil@127.0.0.1:8790", "", "", "127.0.0.1:1234", 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://127.0.0.1:8790/client/config", nil)
			r.Host = tc.host
			r.RemoteAddr = tc.peer
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("Sec-Fetch-Site", tc.site)
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, r)
			if w.Code != tc.code {
				t.Fatalf("status %d want %d", w.Code, tc.code)
			}
		})
	}
}
