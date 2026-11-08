package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func withMigrationObservationArgs(t *testing.T) {
	t.Helper()
	previous := os.Args
	os.Args = append(append([]string(nil), os.Args...), "--migration-observe")
	t.Cleanup(func() { os.Args = previous })
}

func TestMigrationObservationHealthPreservesNormalContract(t *testing.T) {
	want := map[string]any{"ok": true, "version": appVersion, "service": serviceModeRequested(), "generation": 4}
	if got := hostHealthPayload(false); !reflect.DeepEqual(got, want) {
		t.Fatalf("normal health contract changed: %#v", got)
	}
	want["migration_observe"] = true
	if got := hostHealthPayload(true); !reflect.DeepEqual(got, want) {
		t.Fatalf("observation health contract wrong: %#v", got)
	}
}

func TestMigrationObservationPreservesConfigAndRequiresExistingFile(t *testing.T) {
	withMigrationObservationArgs(t)
	root := t.TempDir()
	path := filepath.Join(root, "server.json")
	original := []byte("{\r\n  \"api_token\": \"fixture-token\", \"github_token\": \"\", \"servers\": [], \"unknown_future_field\": {\"name\": \"금이 놀이터\"}\r\n}\r\n")
	if err := os.WriteFile(path, original, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadOrCreateConfig(path); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(got, original) {
		t.Fatal("observation load rewrote the preserved config")
	}
	missing := filepath.Join(root, "missing", "server.json")
	if _, err := loadOrCreateConfig(missing); err == nil {
		t.Fatal("observation created a default configuration")
	}
	if _, err := os.Stat(filepath.Dir(missing)); !os.IsNotExist(err) {
		t.Fatal("observation created a missing configuration directory")
	}
}

func TestMigrationObservationBlocksEveryMutationBeforeHandler(t *testing.T) {
	for _, observe := range []bool{false, true} {
		for _, method := range []string{http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete, http.MethodOptions, http.MethodConnect} {
			for _, path := range []string{"/api/server/action", "/api/v4/network/player-location", "/api/v4/update/self/status", "/api/v1/ws", "/future-route"} {
				called := false
				h := migrationObservationGuard(observe, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					called = true
					w.WriteHeader(http.StatusOK)
				}))
				rec := httptest.NewRecorder()
				h.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
				blocked := observe && ((method != http.MethodGet && method != http.MethodHead) || path == "/api/v1/ws")
				if called == blocked || (blocked && rec.Code != http.StatusLocked) {
					t.Fatalf("observe=%v method=%s path=%s called=%v status=%d", observe, method, path, called, rec.Code)
				}
				if blocked && !strings.Contains(rec.Body.String(), "마이그레이션 확인 모드") {
					t.Fatal("observation rejection lost its Korean explanation")
				}
			}
		}
	}
}

func TestMigrationObservationDeviceAuthDoesNotRewriteTrustStore(t *testing.T) {
	withMigrationObservationArgs(t)
	oldPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	t.Cleanup(func() { configPath = oldPath })
	original := []byte(fmt.Sprintf("[{\"id\":\"fixture\",\"name\":\"금이\",\"token_hash\":%q,\"last_seen\":\"original\",\"future\":true}]\r\n", hashToken("fixture-device-token")))
	if err := os.WriteFile(devicesPath(), original, 0600); err != nil {
		t.Fatal(err)
	}
	if d, ok := trustedDeviceForToken("fixture-device-token"); !ok || d.ID != "fixture" {
		t.Fatal("existing device authentication stopped working")
	}
	got, err := os.ReadFile(devicesPath())
	if err != nil || !bytes.Equal(got, original) {
		t.Fatal("observation device authentication changed the trust store")
	}
}

// Exercise actual Host startup in an isolated subprocess. Fake schedules/jobs,
// Agent config, plugin config and launchers make unintended startup work visible.
// No Windows service, production path or production port is used.
func TestMigrationObservationHostSubprocess(t *testing.T) {
	if os.Getenv("GSC_TEST_MIGRATION_OBSERVE") == "1" {
		if err := runHostCore(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		os.Exit(0)
	}
	root := t.TempDir()
	ln, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()
	agentDir := filepath.Join(root, "agent")
	serverDir := filepath.Join(root, "disposable-server")
	config := Config{
		Port: port, Bind: "127.0.0.1", APIToken: "observe-fixture-token", AutoStartAgent: true,
		Agent:   AgentConfig{HealthURL: "http://127.0.0.1:1/health", StateURL: "http://127.0.0.1:1/state", WorkingDir: agentDir},
		Update:  UpdateConfig{Enabled: false, PublicKeyPath: filepath.Join(root, "missing-public-key.pem")},
		Servers: []ServerConfig{{ID: "playground", Name: "금이 놀이터", Path: serverDir, JavaPort: 0, AutoStart: true, RestartOnCrash: true, StartCommand: "start.bat"}},
	}
	configBytes, _ := json.MarshalIndent(config, "", "  ")
	fixtures := map[string][]byte{
		"server.json":                                              configBytes,
		"agent/agent.properties":                                   []byte("servers=original\r\nsecret=unsafe\r\n"),
		"disposable-server/server.properties":                      []byte("server-port=0\r\n"),
		"disposable-server/start.bat":                              []byte("@echo should-never-launch>migration-started.txt\r\n"),
		"disposable-server/plugins/GeumyiDiscordStatus/config.yml": []byte("server:\n  name: original\n"),
		"automations.json":                                         []byte("[]\n"),
		"jobs/control-jobs.jsonl":                                  []byte("{\"id\":\"queued-fixture\",\"status\":\"running\"}\n"),
	}
	for rel, content := range fixtures {
		path := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, content, 0600); err != nil {
			t.Fatal(err)
		}
	}
	before := migrationFixtureSnapshot(t, root)
	cmd := exec.Command(os.Args[0], "-test.run=^TestMigrationObservationHostSubprocess$", "--", "--migration-observe", "--config", filepath.Join(root, "server.json"))
	cmd.Env = append(os.Environ(), "GSC_TEST_MIGRATION_OBSERVE=1")
	cmd.Dir = root
	var output bytes.Buffer
	cmd.Stdout, cmd.Stderr = &output, &output
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	client := &http.Client{Timeout: 2 * time.Second}
	base := fmt.Sprintf("http://127.0.0.1:%d", port)
	deadline := time.Now().Add(20 * time.Second)
	var health map[string]any
	for time.Now().Before(deadline) {
		resp, e := client.Get(base + "/api/health")
		if e == nil {
			_ = json.NewDecoder(resp.Body).Decode(&health)
			_ = resp.Body.Close()
			if health["ok"] == true {
				break
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	if health["migration_observe"] != true || health["version"] != appVersion {
		t.Fatalf("observation Host health missing or wrong: %#v", health)
	}
	for _, path := range []string{"/api/settings/public", "/api/v4/update/self/status"} {
		req, _ := http.NewRequest(http.MethodGet, base+path, nil)
		req.Header.Set("Authorization", "Bearer observe-fixture-token")
		resp, e := client.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("read API %s returned %d", path, resp.StatusCode)
		}
	}
	resp, err := client.Post(base+"/api/agent/start", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusLocked {
		t.Fatalf("mutation status=%d", resp.StatusCode)
	}
	// Normal startup supervision begins after five seconds.
	time.Sleep(6 * time.Second)
	if after := migrationFixtureSnapshot(t, root); !reflect.DeepEqual(before, after) {
		t.Fatal("observation startup or read APIs changed the disposable configuration/runtime tree")
	}
}

func migrationFixtureSnapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	files := map[string]string{}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if info.IsDir() {
			files[rel+"/"] = "directory"
			return nil
		}
		b, err := os.ReadFile(path)
		if err == nil {
			files[rel] = string(b)
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return files
}
