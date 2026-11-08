package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type externalFixtureTransport struct {
	next   http.RoundTripper
	target *url.URL
}

func (tr externalFixtureTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	q := req.Clone(req.Context())
	u := *req.URL
	u.Scheme = tr.target.Scheme
	u.Host = tr.target.Host
	q.URL = &u
	q.Host = tr.target.Host
	return tr.next.RoundTrip(q)
}
func TestExternalDownloadSeparateTimeoutBudget(t *testing.T) {
	if externalHTTPClient().Timeout != 20*time.Second {
		t.Fatal("metadata budget changed")
	}
	if externalDownloadHTTPClient().Timeout != 2*time.Minute {
		t.Fatal("download budget not bounded to two minutes")
	}
	req, _ := http.NewRequest("GET", "http://untrusted.invalid/file.jar", nil)
	if externalDownloadHTTPClient().CheckRedirect(req, nil) == nil {
		t.Fatal("HTTPS downgrade accepted")
	}
}
func TestExternalDownloadSlowBodyAndCleanup(t *testing.T) {
	payload := bytes.Repeat([]byte("a"), 131072)
	sum := sha256.Sum256(payload)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(payload[:65536])
		w.(http.Flusher).Flush()
		select {
		case <-time.After(80 * time.Millisecond):
			w.Write(payload[65536:])
		case <-r.Context().Done():
		}
	}))
	defer srv.Close()
	target, _ := url.Parse(srv.URL)
	artifact := ExternalArtifact{URL: "https://download.geysermc.org/fixture.jar", SHA256: hex.EncodeToString(sum[:]), SHA256Verified: true}
	for _, tc := range []struct {
		name   string
		budget time.Duration
		ok     bool
	}{{"old_short_budget", 20 * time.Millisecond, false}, {"bounded_long_budget", time.Second, true}} {
		t.Run(tc.name, func(t *testing.T) {
			client := &http.Client{Timeout: tc.budget, Transport: externalFixtureTransport{srv.Client().Transport, target}}
			dst := filepath.Join(t.TempDir(), "Geyser-Velocity.jar")
			err := downloadExternalVerifiedWithClient(context.Background(), artifact, dst, client)
			if (err == nil) != tc.ok {
				t.Fatalf("ok=%v error=%v", tc.ok, err)
			}
			if _, e := os.Stat(dst + ".tmp"); !os.IsNotExist(e) {
				t.Fatal("temporary download left behind")
			}
			if tc.ok {
				got, e := os.ReadFile(dst)
				if e != nil || !bytes.Equal(got, payload) {
					t.Fatal("verified payload mismatch")
				}
			} else if _, e := os.Stat(dst); !os.IsNotExist(e) {
				t.Fatal("failed download published")
			}
		})
	}
}
func TestExternalDownloadHashMismatchAndCancellation(t *testing.T) {
	payload := bytes.Repeat([]byte("b"), 131072)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(payload) }))
	defer srv.Close()
	target, _ := url.Parse(srv.URL)
	client := &http.Client{Timeout: time.Second, Transport: externalFixtureTransport{srv.Client().Transport, target}}
	artifact := ExternalArtifact{URL: "https://download.geysermc.org/fixture.jar", SHA256: strings.Repeat("0", 64), SHA256Verified: true}
	dst := filepath.Join(t.TempDir(), "test.jar")
	if err := downloadExternalVerifiedWithClient(context.Background(), artifact, dst, client); err == nil || !strings.Contains(err.Error(), "SHA-256 mismatch") {
		t.Fatalf("missing digest rejection: %v", err)
	}
	if _, e := os.Stat(dst); !os.IsNotExist(e) {
		t.Fatal("unverified output published")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := downloadExternalVerifiedWithClient(ctx, artifact, dst, client); err == nil {
		t.Fatal("cancellation ignored")
	}
	if _, e := os.Stat(dst + ".tmp"); !os.IsNotExist(e) {
		t.Fatal("cancelled temp left behind")
	}
	artifact.URL = "https://untrusted.invalid/test.jar"
	if err := downloadExternalVerifiedWithClient(context.Background(), artifact, dst, client); err == nil {
		t.Fatal("untrusted source accepted")
	}
}
func TestExternalBlockedAttemptPersistedAndCannotApply(t *testing.T) {
	old := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = old }()
	root := filepath.Join(v4Root(), "Staging", "External", "20991108-210000.000000001")
	plan := map[string]any{"schema": 1, "root": root, "staged": []any{}, "blocked": []map[string]string{{"component": "geyser", "reason": "test timeout"}}, "live_files_modified": false}
	if err := persistExternalStagePlan(root, plan); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(root, "external-stage-plan.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if json.Unmarshal(data, &got) != nil || len(got["blocked"].([]any)) != 1 {
		t.Fatal("blocked result missing")
	}
	if latestExternalStageRoot() != root {
		t.Fatal("latest failed attempt not discoverable")
	}
	if _, err := readExternalStagePlan(""); err == nil || !strings.Contains(err.Error(), "no verified artifacts") {
		t.Fatalf("empty plan must not apply: %v", err)
	}
}
func TestExternalStagingConcurrencyAndUnknownComponent(t *testing.T) {
	externalStageMu.Lock()
	rec := httptest.NewRecorder()
	apiV4ExternalUpdateStage(rec, httptest.NewRequest("POST", "/", strings.NewReader(`{"components":["geyser"]}`)))
	externalStageMu.Unlock()
	if rec.Code != http.StatusConflict {
		t.Fatalf("duplicate stage status=%d", rec.Code)
	}
	rec = httptest.NewRecorder()
	apiV4ExternalUpdateStage(rec, httptest.NewRequest("POST", "/", strings.NewReader(`{"components":["unknown"]}`)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("unknown component status=%d", rec.Code)
	}
}
