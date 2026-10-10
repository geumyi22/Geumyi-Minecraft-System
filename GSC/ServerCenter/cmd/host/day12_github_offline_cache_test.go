package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// This is a disposable-network TEST of GSC GitHub metadata cache behavior.
// It binds a loopback httptest server on a random port, closes it, and then
// exercises the real production githubPublicJSON function while the source is
// unreachable. It does not affect the operator's OS network/firewall, running
// GSC service, Minecraft worlds, or Golden backups. Cached public metadata is
// NOT equivalent to verified signed deployment artifacts or Paper startup.
func TestDay12GitHubMetadataNetworkOfflineWithinStaleWindow(t *testing.T) {
	oldPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldPath }()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"test_release":"offline-metadata-candidate"}`))
	}))
	client := &http.Client{Timeout: 650 * time.Millisecond}
	resourceURL := server.URL + "/day12/offline-test"
	original, initiallyCached, err := githubPublicJSON(client, resourceURL, 1<<20)
	if err != nil || initiallyCached {
		server.Close()
		t.Fatalf("initial metadata fetch failed: cached=%v err=%v", initiallyCached, err)
	}
	server.Close()

	// Force the on-disk cache out of the fresh 15-minute window but within
	// the 24-hour stale fallback window. This is a local test-only cache.
	cachePath := githubPublicCachePath(resourceURL)
	b, err := os.ReadFile(cachePath)
	if err != nil { t.Fatal(err) }
	var cached githubPublicCacheFile
	if err := json.Unmarshal(b, &cached); err != nil { t.Fatal(err) }
	cached.FetchedAt = time.Now().Add(-30 * time.Minute).UTC().Format(time.RFC3339)
	updated, err := json.Marshal(cached)
	if err != nil { t.Fatal(err) }
	if err := os.WriteFile(cachePath, updated, 0600); err != nil { t.Fatal(err) }

	actual, usedCache, err := githubPublicJSON(client, resourceURL, 1<<20)
	if err != nil || !usedCache || string(actual) != string(original) {
		t.Fatalf("network closed but safe stale public metadata was not reused: usedCache=%v err=%v", usedCache, err)
	}
}

func TestDay12GitHubMetadataNetworkOfflineAfterStaleLimitIsFailClosed(t *testing.T) {
	oldPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldPath }()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"test_release":"expired-cache"}`))
	}))
	client := &http.Client{Timeout: 650 * time.Millisecond}
	resourceURL := server.URL + "/day12/expired-cache"
	if _, cached, err := githubPublicJSON(client, resourceURL, 1<<20); err != nil || cached {
		server.Close()
		t.Fatalf("could not seed disposable metadata cache: cached=%v err=%v", cached, err)
	}
	server.Close()

	cachePath := githubPublicCachePath(resourceURL)
	b, err := os.ReadFile(cachePath)
	if err != nil { t.Fatal(err) }
	var cached githubPublicCacheFile
	if err := json.Unmarshal(b, &cached); err != nil { t.Fatal(err) }
	cached.FetchedAt = time.Now().Add(-25 * time.Hour).UTC().Format(time.RFC3339)
	updated, err := json.Marshal(cached)
	if err != nil { t.Fatal(err) }
	if err := os.WriteFile(cachePath, updated, 0600); err != nil { t.Fatal(err) }

	result, usedCache, err := githubPublicJSON(client, resourceURL, 1<<20)
	if err == nil || usedCache || len(result) != 0 {
		t.Fatalf("expired, untrusted offline metadata must NOT be returned: usedCache=%v err=%v bytes=%d", usedCache, err, len(result))
	}
}
