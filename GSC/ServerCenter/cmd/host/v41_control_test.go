package main

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

func TestControlHistoryRetainsRunningJob(t *testing.T) {
	controlJobMu.Lock()
	defer controlJobMu.Unlock()
	savedJobs, savedOrder := controlJobs, controlJobOrder
	defer func() { controlJobs, controlJobOrder = savedJobs, savedOrder }()
	controlJobs = map[string]*ControlJob{"busy": {ID: "busy", Status: "running"}}
	controlJobOrder = []string{"busy"}
	for n := 0; n < 500; n++ {
		id := strconv.Itoa(n)
		controlJobs[id] = &ControlJob{ID: id, Status: "completed"}
		controlJobOrder = append(controlJobOrder, id)
	}
	pruneControlHistory()
	if len(controlJobs) != 500 || len(controlJobOrder) != 500 || controlJobOrder[0] != "busy" || controlJobs["0"] != nil {
		t.Fatal("active job or history cap lost during retention")
	}
}

func TestControlQueueConcurrentLastSlot(t *testing.T) {
	const server = "fixture-queue"
	configMu.Lock()
	oldCfg, oldPath := cfg, configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	cfg = Config{Servers: []ServerConfig{{ID: server}}}
	configMu.Unlock()
	defer func() { configMu.Lock(); cfg, configPath = oldCfg, oldPath; configMu.Unlock() }()
	controlJobMu.Lock()
	oldJobs, oldOrder, oldQueues := controlJobs, controlJobOrder, controlJobQueues
	q := make(chan string, 1)
	controlJobs = map[string]*ControlJob{}
	controlJobOrder = nil
	controlJobQueues = map[string]chan string{server: q} // no worker; no server action can execute
	controlJobMu.Unlock()
	defer func() {
		controlJobMu.Lock()
		controlJobs, controlJobOrder, controlJobQueues = oldJobs, oldOrder, oldQueues
		controlJobMu.Unlock()
	}()
	const callers = 12
	start := make(chan struct{})
	done := make(chan error, callers)
	for i := 0; i < callers; i++ {
		go func() {
			<-start
			_, err := enqueueControlJob(server, "stop", 0, authPrincipal{}, "test", "")
			done <- err
		}()
	}
	close(start)
	accepted := 0
	timeout := time.After(4 * time.Second)
	for i := 0; i < callers; i++ {
		select {
		case err := <-done:
			if err == nil {
				accepted++
			} else if err.Error() != "server job queue is full" {
				t.Fatal(err)
			}
		case <-timeout:
			t.Fatal("queue submit blocked after the last slot was reserved")
		}
	}
	if accepted != 1 || len(q) != 1 || len(controlJobOrder) != 1 {
		t.Fatal("unexpected queue admission")
	}
}

func TestParseV1ServerPath(t *testing.T) {
	cases := []struct {
		path, id, suffix string
	}{
		{"/api/v1/servers/wild", "wild", ""},
		{"/api/v1/servers/wild/players", "wild", "players"},
		{"/api/v1/servers/playground/health", "playground", "health"},
	}
	for _, tc := range cases {
		id, suffix := parseV1ServerPath(tc.path)
		if id != tc.id || suffix != tc.suffix {
			t.Fatalf("parse %q = %q/%q, want %q/%q", tc.path, id, suffix, tc.id, tc.suffix)
		}
	}
}

func TestDeriveServerStateBasic(t *testing.T) {
	s := ServerConfig{ID: "state-test"}
	if got := deriveServerState(s, ServerStatus{Online: true, MC: MCStatus{OK: true}, RCONPortOpen: true, GDSAPIOnline: true}); got != "ONLINE" {
		t.Fatalf("online state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{}); got != "OFFLINE" {
		t.Fatalf("offline state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{DesiredRunning: true}); got != "RECOVERING" {
		t.Fatalf("recovering state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{Launch: LaunchStatus{Phase: "starting"}}); got != "STARTING" {
		t.Fatalf("starting state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{Launch: LaunchStatus{FailureCode: "java-version"}}); got != "BOOT_FAILED" {
		t.Fatalf("boot failed state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{Online: true, MC: MCStatus{OK: true}, RCONPortOpen: true, GDSAPIOnline: false}); got != "DEGRADED" {
		t.Fatalf("degraded state = %s", got)
	}
	if got := deriveServerState(s, ServerStatus{Online: true, MC: MCStatus{OK: true}, RCONPortOpen: false, GDSAPIOnline: true}); got != "ONLINE" {
		t.Fatalf("rcon-only warning must remain ONLINE, got %s", got)
	}
}

func TestReconcileConfiguredMaxPlayersPrefersServerProperties(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte("max-players=6\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	mc := MCStatus{OK: true, Max: 2026}
	reconcileConfiguredMaxPlayers(dir, &mc)
	if mc.Max != 6 || mc.ConfiguredMax != 6 || mc.ReportedMax != 2026 {
		t.Fatalf("reconciled max = %+v", mc)
	}
	if mc.MaxSource != "server.properties (status mismatch)" {
		t.Fatalf("max source = %q", mc.MaxSource)
	}
}

func TestInitAuditSeqRestoresHighestPersistedSequence(t *testing.T) {
	oldConfigPath := configPath
	oldSeq := auditSeq.Load()
	t.Cleanup(func() {
		configPath = oldConfigPath
		auditSeq.Store(oldSeq)
	})

	root := t.TempDir()
	configPath = filepath.Join(root, "config.json")
	if err := os.MkdirAll(filepath.Join(root, "audit"), 0o755); err != nil {
		t.Fatal(err)
	}
	backup := `{"seq":41,"time":"2026-09-24T00:00:00Z","actor_kind":"local","method":"GET","path":"/","action":"test","result":"ok"}` + "\n"
	current := `{"seq":57,"time":"2026-09-24T00:00:01Z","actor_kind":"local","method":"GET","path":"/","action":"test","result":"ok"}` + "\n"
	if err := os.WriteFile(auditPath()+".1", []byte(backup), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(auditPath(), []byte(current), 0o644); err != nil {
		t.Fatal(err)
	}

	auditSeq.Store(0)
	initAuditSeq()
	if got := auditSeq.Load(); got != 57 {
		t.Fatalf("audit sequence = %d, want 57", got)
	}
}

func TestEffectivePrincipalLoopbackDelegation(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "http://127.0.0.1/api/v1/servers/wild/actions", nil)
	r.RemoteAddr = "127.0.0.1:54321"
	r.Header.Set("X-GSC-Actor-Id", "123456789")
	r.Header.Set("X-GSC-Actor", "DiscordUser")
	r.Header.Set("X-GSC-Source", "discord-agent")
	r = r.WithContext(context.WithValue(r.Context(), authContextKey{}, authPrincipal{Kind: "local", ID: "loopback", Name: "Local GSC"}))
	p := effectivePrincipal(r)
	if p.Kind != "delegated" || p.ID != "123456789" || p.Name != "DiscordUser" {
		t.Fatalf("unexpected delegated principal: %+v", p)
	}
	if got := requestControlSource(r); got != "discord-agent" {
		t.Fatalf("unexpected source: %q", got)
	}
}

func TestEffectivePrincipalLoopbackUnicodeDelegation(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "http://127.0.0.1/api/v1/servers/wild/actions", nil)
	r.RemoteAddr = "127.0.0.1:54321"
	r.Header.Set("X-GSC-Actor-Id", "123456789")
	r.Header.Set("X-GSC-Actor-B64", base64.RawURLEncoding.EncodeToString([]byte("성민")))
	r = r.WithContext(context.WithValue(r.Context(), authContextKey{}, authPrincipal{Kind: "local", ID: "loopback", Name: "Local GSC"}))
	p := effectivePrincipal(r)
	if p.Kind != "delegated" || p.ID != "123456789" || p.Name != "성민" {
		t.Fatalf("unexpected unicode delegated principal: %+v", p)
	}
}

func TestEffectivePrincipalRejectsRemoteDelegation(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "http://gsc/api/v1/servers/wild/actions", nil)
	r.RemoteAddr = "192.0.2.10:12345"
	r.Header.Set("X-GSC-Actor-Id", "spoof")
	r.Header.Set("X-GSC-Actor", "Spoofed")
	r = r.WithContext(context.WithValue(r.Context(), authContextKey{}, authPrincipal{Kind: "api_token", ID: "host-token", Name: "Host API Token"}))
	p := effectivePrincipal(r)
	if p.Kind != "api_token" || p.ID != "host-token" {
		t.Fatalf("remote delegation should be ignored: %+v", p)
	}
}
