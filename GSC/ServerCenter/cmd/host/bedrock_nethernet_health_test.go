package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestNetherNetDiscoveryDoesNotAcceptArbitraryHTTP(t *testing.T) {
	valid := `{"dataVersion":7,"protocol":2225,"version":"26.60","transportLayer":2,"connection":4}`
	for _, tc := range []struct {
		name, body string
		ok         bool
	}{{"nethernet", valid, true}, {"empty", "{}", false}, {"html", "<html>OK</html>", false}, {"wrong_transport", strings.Replace(valid, `"transportLayer":2`, `"transportLayer":0`, 1), false}, {"missing_version", strings.Replace(valid, `"version":"26.60"`, `"version":""`, 1), false}, {"oversized", valid + strings.Repeat(" ", 65536), false}} {
		t.Run(tc.name, func(t *testing.T) {
			if got := matchesNetherNetJoin([]byte(tc.body)); got != tc.ok {
				t.Fatalf("got %v want %v", got, tc.ok)
			}
		})
	}
}
func TestNetherNetReadinessOverRealHTTP(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/join" {
			t.Error("wrong discovery path")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"dataVersion":7,"protocol":2225,"version":"26.60","transportLayer":2}`))
	}))
	defer s.Close()
	_, p, _ := net.SplitHostPort(s.Listener.Addr().String())
	port, _ := strconv.Atoi(p)
	if !probeBedrockNetherNet(port) || !probeBedrockTransportReady(port) {
		t.Fatal("valid NetherNet discovery rejected")
	}
}
func TestNetherNetDiscoveryRejectsRedirect(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "https://example.invalid/", http.StatusFound)
	}))
	defer s.Close()
	_, p, _ := net.SplitHostPort(s.Listener.Addr().String())
	port, _ := strconv.Atoi(p)
	if probeBedrockNetherNet(port) {
		t.Fatal("redirect accepted as healthy")
	}
}
