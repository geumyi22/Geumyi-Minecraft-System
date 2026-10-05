package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	githubPublicCacheFresh = 15 * time.Minute
	githubPublicCacheStale = 24 * time.Hour
)

type githubPublicCacheFile struct {
	URL       string          `json:"url"`
	FetchedAt string          `json:"fetched_at"`
	Body      json.RawMessage `json:"body"`
}

var githubPublicMu sync.Mutex

func githubPublicCachePath(rawURL string) string {
	sum := sha256.Sum256([]byte(rawURL))
	return filepath.Join(v4Root(), "Cache", "GitHubAPI", hex.EncodeToString(sum[:])+".json")
}

func readGitHubPublicCache(rawURL string) ([]byte, time.Time, bool) {
	b, err := os.ReadFile(githubPublicCachePath(rawURL))
	if err != nil {
		return nil, time.Time{}, false
	}
	var c githubPublicCacheFile
	if json.Unmarshal(b, &c) != nil || c.URL != rawURL || !json.Valid(c.Body) {
		return nil, time.Time{}, false
	}
	t, err := time.Parse(time.RFC3339, c.FetchedAt)
	if err != nil {
		return nil, time.Time{}, false
	}
	return append([]byte(nil), c.Body...), t, true
}

func writeGitHubPublicCache(rawURL string, body []byte) {
	if !json.Valid(body) {
		return
	}
	p := githubPublicCachePath(rawURL)
	if os.MkdirAll(filepath.Dir(p), 0755) != nil {
		return
	}
	c := githubPublicCacheFile{
		URL: rawURL,
		FetchedAt: time.Now().UTC().Format(time.RFC3339),
		Body: append(json.RawMessage(nil), body...),
	}
	b, err := json.Marshal(c)
	if err != nil {
		return
	}
	tmp := p + ".tmp"
	if os.WriteFile(tmp, b, 0600) == nil {
		_ = os.Remove(p)
		_ = os.Rename(tmp, p)
	}
}

func githubRateLimitError(resp *http.Response) error {
	if resp == nil {
		return fmt.Errorf("GitHub API request failed")
	}
	msg := fmt.Sprintf("GitHub API HTTP %d", resp.StatusCode)
	remaining := strings.TrimSpace(resp.Header.Get("X-RateLimit-Remaining"))
	reset := strings.TrimSpace(resp.Header.Get("X-RateLimit-Reset"))
	retry := strings.TrimSpace(resp.Header.Get("Retry-After"))
	if remaining != "" {
		msg += " · rate remaining=" + remaining
	}
	if reset != "" {
		if sec, err := strconv.ParseInt(reset, 10, 64); err == nil {
			msg += " · reset=" + time.Unix(sec, 0).Local().Format("15:04:05")
		}
	}
	if retry != "" {
		msg += " · retry-after=" + retry + "s"
	}
	return fmt.Errorf("%s", msg)
}

// githubPublicJSON protects the server from anonymous GitHub API rate-limit
// spikes caused by dashboard refreshes. Successful public JSON responses are
// persisted for a short TTL. If GitHub returns 403/429 or is temporarily
// unreachable, a recent immutable-metadata cache may be used. Signed GSC
// manifests are still independently signature-verified by the caller.
func githubPublicJSON(client *http.Client, rawURL string, max int64) ([]byte, bool, error) {
	githubPublicMu.Lock()
	defer githubPublicMu.Unlock()

	cached, fetched, haveCache := readGitHubPublicCache(rawURL)
	if haveCache && time.Since(fetched) >= 0 && time.Since(fetched) <= githubPublicCacheFresh {
		return cached, true, nil
	}

	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	if token := strings.TrimSpace(configSnapshot().GitHubToken); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := client.Do(req)
	if err != nil {
		if haveCache && time.Since(fetched) >= 0 && time.Since(fetched) <= githubPublicCacheStale {
			return cached, true, nil
		}
		return nil, false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		if (resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusTooManyRequests) &&
			haveCache && time.Since(fetched) >= 0 && time.Since(fetched) <= githubPublicCacheStale {
			return cached, true, nil
		}
		return nil, false, githubRateLimitError(resp)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, max+1))
	if err != nil {
		return nil, false, err
	}
	if int64(len(body)) > max {
		return nil, false, fmt.Errorf("GitHub API response too large")
	}
	if !json.Valid(body) {
		return nil, false, fmt.Errorf("GitHub API response is not valid JSON")
	}
	writeGitHubPublicCache(rawURL, body)
	return body, false, nil
}
