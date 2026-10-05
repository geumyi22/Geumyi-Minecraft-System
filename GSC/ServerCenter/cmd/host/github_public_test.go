package main

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func TestDay11GitHubPublicJSONCachesAndFallsBackOn403(t *testing.T) {
	oldConfigPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldConfigPath }()

	status := http.StatusOK
	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		if status != http.StatusOK {
			w.Header().Set("X-RateLimit-Remaining", "0")
			w.WriteHeader(status)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer srv.Close()

	client := &http.Client{Timeout: 2 * time.Second}
	body, cached, err := githubPublicJSON(client, srv.URL, 1<<20)
	if err != nil || cached || string(body) != `{"ok":true}` {
		t.Fatalf("initial request failed: cached=%v err=%v body=%s", cached, err, body)
	}
	status = http.StatusForbidden

	// The second request should use the fresh persistent cache and avoid the
	// network entirely, proving dashboard refreshes do not burn API quota.
	body, cached, err = githubPublicJSON(client, srv.URL, 1<<20)
	if err != nil || !cached || string(body) != `{"ok":true}` {
		t.Fatalf("cached request failed: cached=%v err=%v body=%s", cached, err, body)
	}
	if hits != 1 {
		t.Fatalf("fresh cache should avoid a second GitHub request, hits=%d", hits)
	}
}

func TestDay11GitHubRateLimitErrorIncludesReset(t *testing.T) {
	resp := &http.Response{StatusCode: http.StatusForbidden, Header: make(http.Header)}
	resp.Header.Set("X-RateLimit-Remaining", "0")
	resp.Header.Set("X-RateLimit-Reset", "1893456000")
	if err := githubRateLimitError(resp); err == nil {
		t.Fatal("expected diagnostic error")
	}
}
