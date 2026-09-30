package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
)

func TestDay10LoopbackOnlyRejectsRemote(t *testing.T) {
	called := false
	h := loopbackOnly(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v4/network/server-state?id=wild", nil)
	req.RemoteAddr = "203.0.113.10:4567"
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("remote network API status=%d want 403", w.Code)
	}
	if called {
		t.Fatal("remote request reached loopback-only handler")
	}
}

func TestDay10LoopbackOnlyAllowsLocal(t *testing.T) {
	called := false
	h := loopbackOnly(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v4/network/server-state?id=wild", nil)
	req.RemoteAddr = "127.0.0.1:4567"
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusNoContent || !called {
		t.Fatalf("local request status=%d called=%v", w.Code, called)
	}
}

func TestDay10NetworkServerStateAllowsHealthyListeningBackend(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	port := ln.Addr().(*net.TCPAddr).Port

	configMu.Lock()
	oldCfg := cfg
	cfg = Config{
		Update: defaultUpdateConfig(t.TempDir()),
		Servers: []ServerConfig{{
			ID: "wild", Name: "Wild", Role: serverRoleWild,
			JavaPort: port, UpdatePolicy: serverUpdateManaged,
		}},
	}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	setUpdateStatus(UpdateStatus{ServerID: "wild", Phase: "idle"})
	req := httptest.NewRequest(http.MethodGet, "/api/v4/network/server-state?id=wild", nil)
	req.RemoteAddr = net.JoinHostPort("127.0.0.1", strconv.Itoa(45000))
	w := httptest.NewRecorder()
	apiV4NetworkServerState(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("server-state status=%d body=%s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	if !containsJSONBool(body, "move_allowed", true) {
		t.Fatalf("healthy listening backend should allow movement: %s", body)
	}

	setUpdateStatus(UpdateStatus{ServerID: "wild", Phase: "rolling_back"})
	w2 := httptest.NewRecorder()
	apiV4NetworkServerState(w2, req)
	if w2.Code != http.StatusOK {
		t.Fatalf("rollback server-state status=%d body=%s", w2.Code, w2.Body.String())
	}
	if !containsJSONBool(w2.Body.String(), "move_allowed", false) {
		t.Fatalf("rolling-back backend must block movement: %s", w2.Body.String())
	}
}

func containsJSONBool(body, key string, want bool) bool {
	needle := "\"" + key + "\":"
	if want {
		needle += "true"
	} else {
		needle += "false"
	}
	return len(body) > 0 && stringContainsCompact(body, needle)
}

func stringContainsCompact(body, needle string) bool {
	compact := make([]byte, 0, len(body))
	for i := 0; i < len(body); i++ {
		switch body[i] {
		case ' ', '\n', '\r', '\t':
			continue
		default:
			compact = append(compact, body[i])
		}
	}
	return stringIndex(string(compact), needle) >= 0
}

func stringIndex(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
