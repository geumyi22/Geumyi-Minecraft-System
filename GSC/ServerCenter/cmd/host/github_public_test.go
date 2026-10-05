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


func TestDay11GitHubPublicJSONUsesConfiguredAuth(t *testing.T) {
	oldConfigPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldConfigPath }()

	configMu.Lock()
	oldCfg := cfg
	cfg = defaultConfig()
	cfg.GitHubToken = "github_pat_test_token_abcdefghijklmnopqrstuvwxyz"
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	gotAuth := ""
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer srv.Close()

	client := &http.Client{Timeout: 2 * time.Second}
	_, _, err := githubPublicJSON(client, srv.URL+"?auth=1", 1<<20)
	if err != nil {
		t.Fatalf("authenticated request failed: %v", err)
	}
	if gotAuth != "Bearer "+cfg.GitHubToken {
		t.Fatalf("Authorization header missing or wrong: %q", gotAuth)
	}
}


func TestDay11GitHubPublicJSONFreshBypassesFreshCache(t *testing.T) {
	oldConfigPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldConfigPath }()

	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		w.Header().Set("Content-Type", "application/json")
		if hits == 1 {
			_, _ = w.Write([]byte(`{"release":"old"}`))
			return
		}
		_, _ = w.Write([]byte(`{"release":"new"}`))
	}))
	defer srv.Close()

	client := &http.Client{Timeout: 2 * time.Second}
	body, cached, err := githubPublicJSON(client, srv.URL+"?fresh=1", 1<<20)
	if err != nil || cached || string(body) != `{"release":"old"}` {
		t.Fatalf("initial request failed: cached=%v err=%v body=%s", cached, err, body)
	}
	body, cached, err = githubPublicJSONFresh(client, srv.URL+"?fresh=1", 1<<20)
	if err != nil || cached || string(body) != `{"release":"new"}` {
		t.Fatalf("forced refresh failed: cached=%v err=%v body=%s", cached, err, body)
	}
	if hits != 2 {
		t.Fatalf("forced refresh must hit network, hits=%d", hits)
	}
}
