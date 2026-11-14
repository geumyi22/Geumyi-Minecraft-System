package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestInstanceProxyTaskIdentity(t *testing.T) {
	dir := t.TempDir()
	p := ManagedInstance{Dir: dir, TaskName: "Geumyi Day10 Velocity wild"}
	valid := instanceProxyTask{Count: 1, Name: p.TaskName, Path: `\`, State: "Ready", Enabled: true, Directory: dir,
		Executable: filepath.Join(dir, "java.exe"), Arguments: "-Xms256M -Xmx512M -jar velocity.jar", Principal: "SYSTEM", Actions: 1}
	if err := instanceProxyValidateTask(p, valid); err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(*instanceProxyTask){
		"duplicate task":           func(s *instanceProxyTask) { s.Count = 2 },
		"different directory":      func(s *instanceProxyTask) { s.Directory = filepath.Join(dir, "other") },
		"shell wrapper":            func(s *instanceProxyTask) { s.Executable = filepath.Join(dir, "cmd.exe") },
		"other jar":                func(s *instanceProxyTask) { s.Arguments = "-jar paper.jar" },
		"duplicate jar":            func(s *instanceProxyTask) { s.Arguments = "-jar velocity.jar -jar paper.jar" },
		"extra action":             func(s *instanceProxyTask) { s.Actions = 2 },
		"different principal":      func(s *instanceProxyTask) { s.Principal = "Guest" },
		"different task directory": func(s *instanceProxyTask) { s.Path = `\Other\` },
	} {
		t.Run(name, func(t *testing.T) {
			bad := valid
			mutate(&bad)
			if instanceProxyValidateTask(p, bad) == nil {
				t.Fatal("accepted mismatched task")
			}
		})
	}
	for _, state := range []instanceProxyTask{{State: "Running"}, {State: "Queued"}, {State: "Ready", LastResult: 1}, {State: "Ready", LastResult: 267009}, {State: "Ready", TCPBusy: true}, {State: "Ready", UDPBusy: true}, {State: "Ready", BridgeBusy: true}} {
		if state.stopped() {
			t.Fatalf("unsafe stopped state: %+v", state)
		}
	}
}

func TestInstanceProxyBridgeAuthAndIdentity(t *testing.T) {
	oldConfig := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	t.Cleanup(func() { configPath = oldConfig })
	p := ManagedInstance{ID: "proxy-test", Dir: t.TempDir(), JavaPort: 25565}
	token := strings.Repeat("a", 64)
	status := instanceProxyBridge{PID: 123, StartTime: 456, Directory: p.Dir, Players: 0, JavaPort: p.JavaPort}
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if r.Header.Get("Authorization") != "Bearer "+token {
			t.Error("missing private bridge authentication")
			w.WriteHeader(403)
			return
		}
		if r.Method == http.MethodPost {
			if r.Header.Get("X-GSC-Expected-PID") != "123" || r.Header.Get("X-GSC-Expected-Start") != "456" {
				t.Error("missing process generation binding")
			}
			w.WriteHeader(202)
			return
		}
		json.NewEncoder(w).Encode(status)
	}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	p.BridgePort, _ = strconv.Atoi(u.Port())
	if err := os.MkdirAll(filepath.Dir(instanceProxySecretPath(p)), 0700); err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(instanceProxySecret{ID: p.ID, Directory: p.Dir, Port: p.BridgePort, Token: token})
	if err := os.WriteFile(instanceProxySecretPath(p), b, 0600); err != nil {
		t.Fatal(err)
	}
	got, err := instanceProxyReadBridge(p)
	if err != nil || got.PID != 123 {
		t.Fatalf("bridge status: %+v %v", got, err)
	}
	resp, err := instanceProxyHTTP(p, http.MethodPost, "/shutdown", &got)
	if err != nil || resp.StatusCode != 202 {
		t.Fatalf("shutdown request failed: %v", err)
	}
	resp.Body.Close()
	status.Directory = filepath.Join(p.Dir, "other")
	if _, err = instanceProxyReadBridge(p); err == nil {
		t.Fatal("accepted another instance's response")
	}
	changed := p
	changed.BridgePort++
	before := requests
	if _, err = instanceProxyReadBridge(changed); err == nil {
		t.Fatal("accepted changed profile")
	}
	if requests != before {
		t.Fatal("contacted bridge using a changed secret binding")
	}
}

func TestInstanceProxyPrepareNeverOverwrites(t *testing.T) {
	path := filepath.Join(t.TempDir(), "control.properties")
	if err := instanceProxyWriteOnce(path, []byte("original")); err != nil {
		t.Fatal(err)
	}
	if err := instanceProxyWriteOnce(path, []byte("original")); err != nil {
		t.Fatal(err)
	}
	if err := instanceProxyWriteOnce(path, []byte("changed")); err == nil {
		t.Fatal("overwrote preexisting settings")
	}
	got, _ := os.ReadFile(path)
	if string(got) != "original" {
		t.Fatal("settings damaged")
	}
}
