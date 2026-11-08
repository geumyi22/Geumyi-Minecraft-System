package main

import (
	"errors"
	"geumyi/servercenter/internal/javaruntime"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPreflightUsesConfiguredJavaPath(t *testing.T) {
	preferred := filepath.Join(t.TempDir(), "portable-java", "bin", "java.exe")
	configMu.Lock()
	oldCfg := cfg
	cfg = Config{Agent: AgentConfig{JavaPath: preferred}}
	configMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	})
	for _, tc := range []struct {
		name string
		err  error
		want string
	}{
		{name: "portable runtime available", want: "ok"},
		{name: "unavailable runtime stays a warning", err: errors.New("test runtime unavailable"), want: "warn"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			called := false
			h := runV4PreflightWithJavaResolver(ServerConfig{ID: "preflight-java"}, func(got string) (javaruntime.Runtime, error) {
				called = true
				if got != preferred {
					t.Fatalf("preflight ignored configured portable Java: got %q want %q", got, preferred)
				}
				return javaruntime.Runtime{Executable: preferred, Version: "25-test"}, tc.err
			})
			if !called {
				t.Fatal("Java was not checked")
			}
			for _, check := range h.Checks {
				if check.Key != "java" {
					continue
				}
				if check.Status != tc.want || (tc.err == nil && !strings.Contains(check.Message, preferred)) {
					t.Fatalf("unexpected Java check: %+v", check)
				}
				return
			}
			t.Fatal("Java result missing from preflight")
		})
	}
}

func TestAsyncStartPreflightFailureIsVisibleWithoutLaunching(t *testing.T) {
	root := t.TempDir()
	s := ServerConfig{ID: "preflight-start-failure", Name: "검사 서버", Path: filepath.Join(root, "missing-server")}
	configMu.Lock()
	oldCfg, oldPath := cfg, configPath
	cfg, configPath = Config{Servers: []ServerConfig{s}}, filepath.Join(root, "server.json")
	configMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		cfg, configPath = oldCfg, oldPath
		configMu.Unlock()
		runtimeMu.Lock()
		delete(launchStates, s.ID)
		runtimeMu.Unlock()
		setDesired(s.ID, false)
	})
	setDesired(s.ID, false)
	runtimeMu.Lock()
	launchStates[s.ID] = LaunchStatus{Phase: "startup-failed", FailureCode: "old-failure", FailureTitle: "과거 오류"}
	runtimeMu.Unlock()
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/api/server/action", strings.NewReader(`{"id":"preflight-start-failure","action":"start"}`))
	apiAction(w, r)
	if w.Code != http.StatusAccepted {
		t.Fatalf("asynchronous start contract changed: %d %s", w.Code, w.Body.String())
	}
	// The result is asynchronous: wait for both the visible status and its log,
	// not merely HTTP 202. No server command is ever reached for a missing path.
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		state := launchStatus(s.ID)
		log, err := os.ReadFile(launcherLogPath(s.ID))
		events := recentV4Events(10, s.ID)
		if state.Phase != "error" || err != nil || len(events) == 0 {
			time.Sleep(10 * time.Millisecond)
			continue
		}
		if !strings.Contains(state.Message, "시작 전 검사 실패") || !strings.Contains(state.Error, s.Path) {
			t.Fatalf("preflight error missing from dashboard status: %+v", state)
		}
		if state.FailureCode != "" || state.FailureTitle != "" {
			t.Fatalf("stale startup failure still hides current error: %+v", state)
		}
		if !strings.Contains(string(log), state.Error) || !strings.Contains(string(log), "start:") {
			t.Fatalf("preflight failure missing from new launcher log: %s", log)
		}
		if getDesired(s.ID) || getLaunch(s.ID) != nil {
			t.Fatal("failed preflight requested a launch or automatic restart")
		}
		if _, err := os.Stat(s.Path); !os.IsNotExist(err) {
			t.Fatalf("failed preflight created or changed the server path: %v", err)
		}
		return
	}
	t.Fatalf("accepted start never reported its preflight failure: %+v", launchStatus(s.ID))
}
