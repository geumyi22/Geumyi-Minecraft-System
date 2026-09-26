package main

import (
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestServerProfileAddAppearsInStatus(t *testing.T) {
	configMu.Lock()
	oldCfg := cfg
	oldPath := configPath
	cfg = Config{Bind: "127.0.0.1", Port: 8787, Servers: []ServerConfig{{ID: "base", Name: "기존", JavaPort: 0, RCONPort: 0, BedrockPort: 0, GDSAPIPort: 0}}}
	configPath = filepath.Join(t.TempDir(), "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldPath
		configMu.Unlock()
	}()

	body := `{"action":"add","server":{"id":"third","name":"추가 서버","path":"","start_command":"start.bat","java_port":0,"rcon_port":0,"bedrock_port":0,"gds_api_port":0,"auto_start":true,"restart_on_crash":false}}`
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v4/server-profile", strings.NewReader(body))
	apiV4ServerProfile(w, r)
	if w.Code != 200 {
		t.Fatalf("add failed: %d %s", w.Code, w.Body.String())
	}

	got, ok := serverByID("third")
	if !ok {
		t.Fatal("new server missing from active config")
	}
	if !got.AutoStart || got.RestartOnCrash {
		t.Fatalf("profile booleans were not preserved: %+v", got)
	}

	sw := httptest.NewRecorder()
	sr := httptest.NewRequest("GET", "/api/status", nil)
	apiStatus(sw, sr)
	if sw.Code != 200 {
		t.Fatalf("status failed: %d %s", sw.Code, sw.Body.String())
	}
	var status FullStatus
	if err := json.Unmarshal(sw.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, s := range status.Servers {
		if s.ID == "third" && s.Name == "추가 서버" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("newly added server not returned by /api/status: %+v", status.Servers)
	}
}
