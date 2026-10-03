package main

import (
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestExistingBatchInUnicodeServerDirectory(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "OneDrive", "Documentos", "Server", "야생 서버 %TEST% & (main)")
	if e := os.MkdirAll(dir, 0755); e != nil {
		t.Fatal(e)
	}
	start := filepath.Join(dir, "start.bat")
	os.WriteFile(start, []byte("@echo off\r\njava -Xmx8G -jar paper.jar nogui\r\n"), 0600)
	os.WriteFile(filepath.Join(dir, "run.bat"), []byte("exit /b 99"), 0600)
	for _, command := range []string{"", "start.bat", `"` + start + `"`, start} {
		line, actual, e := resolveLaunch(command, dir)
		if e != nil {
			t.Fatal(e)
		}
		if actual != start {
			t.Fatalf("wrong batch: %q", actual)
		}
		if strings.Contains(line, dir) || strings.Contains(strings.ToLower(line), "call ") {
			t.Fatalf("batch path must be expanded once: %q", line)
		}
	}
	if _, _, e := resolveLaunch("missing.bat", dir); e == nil {
		t.Fatal("missing custom batch silently accepted")
	}
}
func TestShutdownWaitsForBothServersBeforeAgent(t *testing.T) {
	var stopped atomic.Int32
	release := make(chan struct{})
	began := make(chan struct{}, 2)
	done := make(chan []string, 1)
	go func() {
		done <- stopManagedComponents([]ServerConfig{{ID: "wild"}, {ID: "playground"}}, func(s ServerConfig) (string, error) {
			began <- struct{}{}
			<-release
			stopped.Add(1)
			return "saved", nil
		}, func() error {
			if stopped.Load() != 2 {
				return errors.New("Agent stopped before both worlds finished saving")
			}
			return nil
		})
	}()
	<-began
	<-began
	select {
	case <-done:
		t.Fatal("shutdown completed while servers were still saving")
	default:
	}
	close(release)
	if e := <-done; len(e) != 0 {
		t.Fatal(e)
	}
}
func TestShutdownFailureKeepsAgentAndHostAvailable(t *testing.T) {
	called := false
	failures := stopManagedComponents([]ServerConfig{{Name: "야생"}}, func(ServerConfig) (string, error) { return "save still running", errors.New("timeout") }, func() error { called = true; return nil })
	if called || len(failures) != 1 {
		t.Fatalf("unsafe partial shutdown: called=%v failures=%v", called, failures)
	}
}
func TestFullShutdownBlocksStartAndAgentRevival(t *testing.T) {
	shuttingDown.Store(true)
	defer shuttingDown.Store(false)
	setDesired("test", true)
	setAgentDesired(true)
	if getDesired("test") || getAgentDesired() {
		t.Fatal("shutdown must block desired-running revival")
	}
	if _, e := startServer(ServerConfig{ID: "test"}); e == nil {
		t.Fatal("start accepted during shutdown")
	}
}
func TestShutdownHTTPRejectsGETAndFormPOST(t *testing.T) {
	for _, method := range []string{"GET", "POST"} {
		w := httptest.NewRecorder()
		r := httptest.NewRequest(method, "/api/shutdown", strings.NewReader("{}"))
		apiShutdown(w, r)
		if w.Code != http.StatusMethodNotAllowed && w.Code != http.StatusUnsupportedMediaType {
			t.Fatalf("unsafe shutdown request accepted: %d", w.Code)
		}
	}
}

func TestStatusPollingDoesNotConnectToRCON(t *testing.T) {
	ln, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer ln.Close()

	tcpLn := ln.(*net.TCPListener)
	if e = tcpLn.SetDeadline(time.Now().Add(350 * time.Millisecond)); e != nil {
		t.Fatal(e)
	}

	port := ln.Addr().(*net.TCPAddr).Port
	_ = getServerStatus(ServerConfig{ID: "rcon-no-probe", JavaPort: 0, RCONPort: port, BedrockPort: 0, GDSAPIPort: 0})

	if c, e := ln.Accept(); e == nil {
		c.Close()
		t.Fatal("status polling opened an RCON TCP session")
	} else if ne, ok := e.(net.Error); !ok || !ne.Timeout() {
		t.Fatalf("unexpected accept error: %v", e)
	}
}

func TestRCONStopHandlesExtraAuthPacketAndNoStopReply(t *testing.T) {
	ln, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer ln.Close()
	result := make(chan error, 1)
	go func() {
		c, e := ln.Accept()
		if e != nil {
			result <- e
			return
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(3 * time.Second))
		id, typ, password, e := readRCON(c)
		if e != nil || id != 100 || typ != 3 || password != "test-password" {
			result <- errors.New("wrong auth request")
			return
		}
		writeRCON(c, 100, 0, "")
		writeRCON(c, 100, 2, "")
		id, typ, command, e := readRCON(c)
		if e != nil || id != 101 || typ != 2 || command != "stop" {
			result <- errors.New("stop not delivered")
			return
		}
		// Real servers often close RCON before replying to stop.
		result <- nil
	}()
	if _, e = rconCommand("127.0.0.1", ln.Addr().(*net.TCPAddr).Port, "test-password", "stop"); e != nil {
		t.Fatal(e)
	}
	if e = <-result; e != nil {
		t.Fatal(e)
	}
}
func TestIntentionalStopCommandExactness(t *testing.T) {
	for _, cmd := range []string{"stop", " STOP ", "/stop", " /STOP "} {
		if !isIntentionalStopCommand(cmd) {
			t.Fatalf("expected intentional stop for %q", cmd)
		}
	}
	for _, cmd := range []string{"", "stop now", "stopping", "/stop now", "say stop"} {
		if isIntentionalStopCommand(cmd) {
			t.Fatalf("must not treat %q as intentional stop", cmd)
		}
	}
}

func TestConsoleStopKeepsServerStoppedAfterSuccessfulRCON(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	port := ln.Addr().(*net.TCPAddr).Port
	serverID := "console-stop-success"
	setDesired(serverID, true)
	defer setDesired(serverID, false)

	result := make(chan error, 1)
	go func() {
		conn, e := ln.Accept()
		if e != nil {
			result <- e
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
		id, typ, password, e := readRCON(conn)
		if e != nil || id != 100 || typ != 3 || password != "test-password" {
			result <- errors.New("wrong auth request")
			return
		}
		_ = writeRCON(conn, 100, 2, "")
		id, typ, command, e := readRCON(conn)
		if e != nil || id != 101 || typ != 2 || command != "stop" {
			result <- errors.New("stop not delivered")
			return
		}
		result <- nil
	}()

	s := ServerConfig{ID: serverID, RCONPort: port}
	if _, err = runServerConsoleRCON(s, "test-password", " /STOP "); err != nil {
		t.Fatal(err)
	}
	if getDesired(serverID) {
		t.Fatal("successful console stop must leave desired_running=false")
	}
	if err = <-result; err != nil {
		t.Fatal(err)
	}
}

func TestConsoleStopRestoresDesiredWhenRCONDeliveryFails(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()

	serverID := "console-stop-fail"
	setDesired(serverID, true)
	defer setDesired(serverID, false)
	s := ServerConfig{ID: serverID, RCONPort: port}
	if _, err = runServerConsoleRCON(s, "test-password", "stop"); err == nil {
		t.Fatal("expected RCON connection failure")
	}
	if !getDesired(serverID) {
		t.Fatal("failed console stop must restore prior desired_running=true")
	}
}

func TestRecentRCONSuccessBridgesPassiveListenerFalseNegative(t *testing.T) {
	port := 34567
	rconRecentMu.Lock()
	old, had := rconRecentSuccess[port]
	rconRecentSuccess[port] = time.Now()
	rconRecentMu.Unlock()
	defer func() {
		rconRecentMu.Lock()
		if had {
			rconRecentSuccess[port] = old
		} else {
			delete(rconRecentSuccess, port)
		}
		rconRecentMu.Unlock()
	}()

	if !rconRecentlyUsable(port, 30*time.Second) {
		t.Fatal("recent authenticated RCON success should count as usable")
	}

	rconRecentMu.Lock()
	rconRecentSuccess[port] = time.Now().Add(-2 * time.Minute)
	rconRecentMu.Unlock()
	if rconRecentlyUsable(port, 30*time.Second) {
		t.Fatal("stale RCON success must not hide a real outage")
	}
}

func TestRCONAuthFailureDoesNotSendStop(t *testing.T) {
	ln, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer ln.Close()
	result := make(chan error, 1)
	go func() {
		c, e := ln.Accept()
		if e != nil {
			result <- e
			return
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(2 * time.Second))
		readRCON(c)
		writeRCON(c, -1, 2, "")
		_, _, _, e = readRCON(c)
		if e == nil {
			result <- errors.New("unauthenticated stop sent")
		} else {
			result <- nil
		}
	}()
	if _, e = rconCommand("127.0.0.1", ln.Addr().(*net.TCPAddr).Port, "wrong", "stop"); e == nil {
		t.Fatal("bad password accepted")
	}
	if e = <-result; e != nil {
		t.Fatal(e)
	}
}
func TestDay10TopologyBedrockStatusUsesProxyPorts(t *testing.T) {
	statusMu.Lock()
	oldCache := udpCache
	oldAt := udpCacheAt
	udpCache = map[int]bool{19132: true, 19133: true, 19134: true}
	udpCacheAt = time.Now()
	statusMu.Unlock()
	defer func() {
		statusMu.Lock()
		udpCache = oldCache
		udpCacheAt = oldAt
		statusMu.Unlock()
	}()

	tests := []struct {
		s ServerConfig
		mode string
		port int
	}{
		{ServerConfig{ID: "wild", Role: serverRoleWild, BedrockPort: 0}, "proxy", 19132},
		{ServerConfig{ID: "playground", Role: serverRolePlayground, BedrockPort: 0}, "proxy", 19133},
		{ServerConfig{ID: "other", Role: serverRoleOther, BedrockPort: 0}, "proxy", 19134},
		{ServerConfig{ID: "lobby", Role: serverRoleLobby, BedrockPort: 0}, "proxy-multi", 0},
	}
	for _, tc := range tests {
		online, mode, port := topologyBedrockStatus(tc.s)
		if !online || mode != tc.mode || port != tc.port {
			t.Fatalf("%s bedrock status online=%v mode=%q port=%d", tc.s.ID, online, mode, port)
		}
	}

	statusMu.Lock()
	udpCache[19133] = false
	statusMu.Unlock()
	online, mode, _ := topologyBedrockStatus(ServerConfig{ID: "lobby", Role: serverRoleLobby, BedrockPort: 0})
	if online || mode != "proxy-multi" {
		t.Fatalf("lobby must report unhealthy when one public Bedrock alias is down: online=%v mode=%q", online, mode)
	}
}

func TestEnvironmentReplacesCaseVariants(t *testing.T) {
	e := setEnvValue([]string{"Path=old", "PATH=duplicate", "JAVA_HOME=shim", "OTHER=keep"}, "PATH", "real-java;system32")
	if len(e) != 3 || envValue(e, "path") != "real-java;system32" || envValue(e, "OTHER") != "keep" {
		t.Fatal(e)
	}
}
func TestConfigSnapshotDoesNotModifyLiveServers(t *testing.T) {
	configMu.Lock()
	old := cfg
	cfg = Config{Servers: []ServerConfig{{ID: "wild", StartCommand: "start.bat"}}}
	configMu.Unlock()
	defer func() { configMu.Lock(); cfg = old; configMu.Unlock() }()
	c := configSnapshot()
	c.Servers[0].StartCommand = "changed.bat"
	if configSnapshot().Servers[0].StartCommand != "start.bat" {
		t.Fatal("snapshot aliases active settings")
	}
}

func TestAgentShutdownURL(t *testing.T) {
	got := agentShutdownURL("http://127.0.0.1:8877/health?x=1#frag")
	if got != "http://127.0.0.1:8877/shutdown" {
		t.Fatalf("unexpected shutdown URL: %q", got)
	}
	if got := agentShutdownURL("not a url"); got != "" {
		t.Fatalf("invalid health URL must not produce shutdown URL: %q", got)
	}
}

func TestRequestAgentGracefulShutdown(t *testing.T) {
	called := make(chan struct{}, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/shutdown" && r.Method == http.MethodPost {
			select {
			case called <- struct{}{}:
			default:
			}
			w.WriteHeader(http.StatusAccepted)
			return
		}
		http.NotFound(w, r)
	}))
	defer srv.Close()
	if !requestAgentGracefulShutdown(srv.URL + "/health") {
		t.Fatal("graceful Agent shutdown request was not accepted")
	}
	select {
	case <-called:
	case <-time.After(time.Second):
		t.Fatal("shutdown endpoint not called")
	}
}
