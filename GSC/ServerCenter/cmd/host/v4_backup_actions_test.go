package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func postBackupActionForTest(t *testing.T, id, file, action string) *httptest.ResponseRecorder {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"id": id, "file": file, "action": action})
	req := httptest.NewRequest(http.MethodPost, "/api/v4/backup/action", bytes.NewReader(body))
	w := httptest.NewRecorder()
	apiV4BackupAction(w, req)
	return w
}

func TestBackupProtectionTrashRestoreAndPermanentDelete(t *testing.T) {
	root := t.TempDir()
	serverDir := filepath.Join(root, "server")
	if err := os.MkdirAll(serverDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "server.properties"), []byte("server-port=25570\n"), 0644); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	oldConfigPath := configPath
	cfg = Config{Servers: []ServerConfig{{ID: "test", Name: "Test", Path: serverDir, JavaPort: 0}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldConfigPath
		configMu.Unlock()
	}()

	v4OpMu.Lock()
	oldOps := v4Operations
	v4Operations = map[string]string{}
	v4OpMu.Unlock()
	defer func() {
		v4OpMu.Lock()
		v4Operations = oldOps
		v4OpMu.Unlock()
	}()

	s, ok := serverByID("test")
	if !ok {
		t.Fatal("test server missing")
	}
	bi, err := createBackup(s, "config", false)
	if err != nil {
		t.Fatal(err)
	}

	w := postBackupActionForTest(t, "test", bi.File, "protect")
	if w.Code != http.StatusOK {
		t.Fatalf("protect failed: %d %s", w.Code, w.Body.String())
	}
	p, err := safeBackupPath(s, bi.File)
	if err != nil {
		t.Fatal(err)
	}
	if !readBackupMeta(p).Protected {
		t.Fatal("backup protection flag was not persisted")
	}

	w = postBackupActionForTest(t, "test", bi.File, "trash")
	if w.Code != http.StatusConflict {
		t.Fatalf("protected backup must not move to trash: %d %s", w.Code, w.Body.String())
	}

	w = postBackupActionForTest(t, "test", bi.File, "unprotect")
	if w.Code != http.StatusOK {
		t.Fatalf("unprotect failed: %d %s", w.Code, w.Body.String())
	}
	w = postBackupActionForTest(t, "test", bi.File, "trash")
	if w.Code != http.StatusOK {
		t.Fatalf("trash failed: %d %s", w.Code, w.Body.String())
	}
	if _, err = safeBackupPath(s, bi.File); err == nil {
		t.Fatal("trashed backup must not remain in active backup roots")
	}
	trashPath, kind, err := safeTrashBackupPath(s, bi.File)
	if err != nil {
		t.Fatal(err)
	}
	if kind != "backup" {
		t.Fatalf("trash kind=%q want backup", kind)
	}
	if _, err = os.Stat(trashPath); err != nil {
		t.Fatal(err)
	}

	w = postBackupActionForTest(t, "test", bi.File, "restore-trash")
	if w.Code != http.StatusOK {
		t.Fatalf("restore-trash failed: %d %s", w.Code, w.Body.String())
	}
	if _, err = safeBackupPath(s, bi.File); err != nil {
		t.Fatalf("restored backup not active: %v", err)
	}

	w = postBackupActionForTest(t, "test", bi.File, "trash")
	if w.Code != http.StatusOK {
		t.Fatalf("second trash failed: %d %s", w.Code, w.Body.String())
	}
	w = postBackupActionForTest(t, "test", bi.File, "delete-permanent")
	if w.Code != http.StatusOK {
		t.Fatalf("permanent delete failed: %d %s", w.Code, w.Body.String())
	}
	if _, _, err = safeTrashBackupPath(s, bi.File); err == nil {
		t.Fatal("permanently deleted backup still exists in trash")
	}
}

func TestBackupActionRejectsPathTraversalAndActivePermanentDelete(t *testing.T) {
	root := t.TempDir()
	serverDir := filepath.Join(root, "server")
	if err := os.MkdirAll(serverDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "server.properties"), []byte("server-port=25570\n"), 0644); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	oldConfigPath := configPath
	cfg = Config{Servers: []ServerConfig{{ID: "test", Name: "Test", Path: serverDir, JavaPort: 0}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldConfigPath
		configMu.Unlock()
	}()

	v4OpMu.Lock()
	oldOps := v4Operations
	v4Operations = map[string]string{}
	v4OpMu.Unlock()
	defer func() {
		v4OpMu.Lock()
		v4Operations = oldOps
		v4OpMu.Unlock()
	}()

	s, _ := serverByID("test")
	bi, err := createBackup(s, "config", false)
	if err != nil {
		t.Fatal(err)
	}

	w := postBackupActionForTest(t, "test", "..\\..\\"+bi.File, "delete-permanent")
	if w.Code != http.StatusNotFound {
		t.Fatalf("permanent delete must only operate on trash: %d %s", w.Code, w.Body.String())
	}
	if _, err = safeBackupPath(s, bi.File); err != nil {
		t.Fatal("active backup was changed by invalid permanent-delete request")
	}
}

func TestRestoreCheckpointIsProtectedByDefault(t *testing.T) {
	root := t.TempDir()
	serverDir := filepath.Join(root, "server")
	if err := os.MkdirAll(serverDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "server.properties"), []byte("server-port=25570\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "bukkit.yml"), []byte("settings: {}\n"), 0644); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	oldConfigPath := configPath
	cfg = Config{Servers: []ServerConfig{{ID: "test", Name: "Test", Path: serverDir, JavaPort: 0}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldConfigPath
		configMu.Unlock()
	}()

	s, ok := serverByID("test")
	if !ok {
		t.Fatal("test server missing")
	}
	cp, err := createBackup(s, "config", true)
	if err != nil {
		t.Fatal(err)
	}
	if !cp.Protected || cp.Kind != "checkpoint" {
		t.Fatalf("checkpoint metadata = %+v", cp)
	}
	p, err := safeBackupPath(s, cp.File)
	if err != nil {
		t.Fatal(err)
	}
	if !readBackupMeta(p).Protected {
		t.Fatal("checkpoint protection metadata was not persisted")
	}

	v4OpMu.Lock()
	oldOps := v4Operations
	v4Operations = map[string]string{}
	v4OpMu.Unlock()
	defer func() {
		v4OpMu.Lock()
		v4Operations = oldOps
		v4OpMu.Unlock()
	}()

	w := postBackupActionForTest(t, "test", cp.File, "trash")
	if w.Code != http.StatusConflict {
		t.Fatalf("protected checkpoint must reject trash: %d %s", w.Code, w.Body.String())
	}
}
