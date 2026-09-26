package main

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func makeTestServerDir(t *testing.T, port string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte("server-port="+port+"\nmax-players=6\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "start.bat"), []byte("@echo off\n"), 0644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestConfiguredServerPathDoesNotDisappearOnPortMismatch(t *testing.T) {
	dir := makeTestServerDir(t, "25566")
	s := ServerConfig{ID: "test", Name: "테스트", Path: dir, JavaPort: 25565}

	if got := configuredServerDir(s); got != filepath.Clean(dir) {
		t.Fatalf("configured path changed: got %q want %q", got, filepath.Clean(dir))
	}
	if got := resolveServerDir(s); got != filepath.Clean(dir) {
		t.Fatalf("valid selected server folder disappeared because of port mismatch: got %q want %q", got, filepath.Clean(dir))
	}

	h := runV4Preflight(s)
	foundPortWarning := false
	for _, c := range h.Checks {
		if c.Key == "server_port" && c.Status == "warn" && strings.Contains(c.Message, "25566") && strings.Contains(c.Message, "25565") {
			foundPortWarning = true
			break
		}
	}
	if !foundPortWarning {
		t.Fatalf("expected separate server_port warning, got: %+v", h.Checks)
	}
}

func TestAPISettingsReturnsSavedPathEvenWhenPortDiffers(t *testing.T) {
	dir := makeTestServerDir(t, "25566")

	configMu.Lock()
	oldCfg := cfg
	cfg = Config{Bind: "127.0.0.1", Port: 8787, Servers: []ServerConfig{{ID: "test", Name: "테스트", Path: dir, JavaPort: 25565, StartCommand: "start.bat"}}}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/settings", nil)
	apiSettings(w, r)
	if w.Code != 200 {
		t.Fatalf("GET /api/settings failed: %d %s", w.Code, w.Body.String())
	}
	var body struct {
		Servers []struct {
			ID   string `json:"id"`
			Path string `json:"path"`
		} `json:"servers"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Servers) != 1 || body.Servers[0].Path != filepath.Clean(dir) {
		t.Fatalf("saved path was not preserved in settings response: %+v", body.Servers)
	}
}

func TestServerStatusKeepsConfiguredPathForInvalidFolder(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing-server")
	s := ServerConfig{ID: "missing", Name: "누락", Path: missing, JavaPort: 0, RCONPort: 0, BedrockPort: 0, GDSAPIPort: 0}
	st := getServerStatus(s)
	if st.ConfiguredDir != filepath.Clean(missing) {
		t.Fatalf("configured_dir missing from status: %+v", st)
	}
	if st.Dir != "" || st.DirValid {
		t.Fatalf("invalid folder should remain configured but unresolved: %+v", st)
	}
}

func TestAPISettingsPostPreservesSelectedPath(t *testing.T) {
	dir := makeTestServerDir(t, "25566")
	root := t.TempDir()

	configMu.Lock()
	oldCfg := cfg
	oldPath := configPath
	cfg = Config{Bind: "127.0.0.1", Port: 8787, Servers: []ServerConfig{{ID: "test", Name: "테스트", JavaPort: 25565, StartCommand: "start.bat"}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldPath
		configMu.Unlock()
	}()

	body := `{"servers":[{"id":"test","path":` + strconv.Quote(dir) + `,"start_command":"start.bat","auto_start":false,"restart_on_crash":false}]}`
	pw := httptest.NewRecorder()
	pr := httptest.NewRequest("POST", "/api/settings", strings.NewReader(body))
	apiSettings(pw, pr)
	if pw.Code != 200 {
		t.Fatalf("POST /api/settings failed: %d %s", pw.Code, pw.Body.String())
	}

	gw := httptest.NewRecorder()
	gr := httptest.NewRequest("GET", "/api/settings", nil)
	apiSettings(gw, gr)
	if gw.Code != 200 {
		t.Fatalf("GET /api/settings failed: %d %s", gw.Code, gw.Body.String())
	}
	var response struct {
		Servers []struct {
			Path string `json:"path"`
		} `json:"servers"`
	}
	if err := json.Unmarshal(gw.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Servers) != 1 || response.Servers[0].Path != filepath.Clean(dir) {
		t.Fatalf("selected path disappeared after POST/GET roundtrip: %+v", response.Servers)
	}
}
