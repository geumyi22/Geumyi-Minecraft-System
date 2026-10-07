package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func postBackupActionRawForTest(t *testing.T, bodyMap map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	body, _ := json.Marshal(bodyMap)
	req := httptest.NewRequest(http.MethodPost, "/api/v4/backup/action", bytes.NewReader(body))
	w := httptest.NewRecorder()
	apiV4BackupAction(w, req)
	return w
}

func postBackupActionForTest(t *testing.T, id, file, action string) *httptest.ResponseRecorder {
	t.Helper()
	body := map[string]string{"id": id, "file": file, "action": action}
	if action == "delete-permanent" {
		body["confirm"] = "DELETE_PERMANENT_BACKUP"
		body["confirm_file"] = filepath.Base(file)
	}
	return postBackupActionRawForTest(t, body)
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

func TestPermanentDeleteRequiresExplicitServerSideConfirmation(t *testing.T) {
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
	bi, err := createBackupWithReason(s, "config", false, "confirmation-test")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = trashBackupFile(s, bi.File); err != nil {
		t.Fatal(err)
	}

	w := postBackupActionRawForTest(t, map[string]string{
		"id": "test", "file": bi.File, "action": "delete-permanent",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("missing confirm token must fail: %d %s", w.Code, w.Body.String())
	}
	if _, _, err = safeTrashBackupPath(s, bi.File); err != nil {
		t.Fatalf("missing-confirm request changed trash: %v", err)
	}

	w = postBackupActionRawForTest(t, map[string]string{
		"id": "test", "file": bi.File, "action": "delete-permanent",
		"confirm": "DELETE_PERMANENT_BACKUP", "confirm_file": "wrong.zip",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("wrong confirm_file must fail: %d %s", w.Code, w.Body.String())
	}
	if _, _, err = safeTrashBackupPath(s, bi.File); err != nil {
		t.Fatalf("wrong-file confirmation changed trash: %v", err)
	}

	w = postBackupActionForTest(t, "test", bi.File, "delete-permanent")
	if w.Code != http.StatusOK {
		t.Fatalf("confirmed permanent delete failed: %d %s", w.Code, w.Body.String())
	}
}

func TestBackupSourceReasonAndRestorePreflight(t *testing.T) {
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

	s, _ := serverByID("test")
	bi, err := createBackupWithReason(s, "config", false, "manual-test")
	if err != nil {
		t.Fatal(err)
	}
	if bi.SourceReason != "manual-test" {
		t.Fatalf("backup reason=%q", bi.SourceReason)
	}
	p, err := safeBackupPath(s, bi.File)
	if err != nil {
		t.Fatal(err)
	}
	m, err := readBackupManifest(p)
	if err != nil {
		t.Fatal(err)
	}
	if m.SourceReason != "manual-test" {
		t.Fatalf("manifest reason=%q", m.SourceReason)
	}
	pre := buildRestorePreflight(s, p)
	if !pre.Ready || !pre.ServerOffline || !pre.BackupVerified || !pre.ServerMatch || !pre.CheckpointReady {
		t.Fatalf("unexpected restore preflight: %+v", pre)
	}
}

func TestNonFullRestoreRollbackUsesProtectedCheckpoint(t *testing.T) {
	root := t.TempDir()
	serverDir := filepath.Join(root, "server")
	if err := os.MkdirAll(serverDir, 0755); err != nil {
		t.Fatal(err)
	}
	props := filepath.Join(serverDir, "server.properties")
	bukkit := filepath.Join(serverDir, "bukkit.yml")
	if err := os.WriteFile(props, []byte("server-port=25570\nmotd=before\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(bukkit, []byte("settings: before\n"), 0644); err != nil {
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

	s, _ := serverByID("test")
	target, err := createBackupWithReason(s, "config", false, "target-before")
	if err != nil {
		t.Fatal(err)
	}
	targetPath, err := safeBackupPath(s, target.File)
	if err != nil {
		t.Fatal(err)
	}
	targetManifest, err := readBackupManifest(targetPath)
	if err != nil {
		t.Fatal(err)
	}

	if err = os.WriteFile(props, []byte("server-port=25570\nmotd=checkpoint\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(bukkit, []byte("settings: checkpoint\n"), 0644); err != nil {
		t.Fatal(err)
	}
	cp, err := createBackupWithReason(s, "config", true, "restore-checkpoint:test")
	if err != nil {
		t.Fatal(err)
	}
	if !cp.Protected {
		t.Fatal("checkpoint must be protected")
	}

	if err = os.WriteFile(props, []byte("server-port=25570\nmotd=partial-target\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err = os.Remove(bukkit); err != nil {
		t.Fatal(err)
	}
	if err = rollbackNonFullRestoreFromCheckpoint(s, cp.File, targetManifest); err != nil {
		t.Fatal(err)
	}
	gotProps, err := os.ReadFile(props)
	if err != nil {
		t.Fatal(err)
	}
	gotBukkit, err := os.ReadFile(bukkit)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(gotProps, []byte("motd=checkpoint")) || !bytes.Contains(gotBukkit, []byte("settings: checkpoint")) {
		t.Fatalf("checkpoint rollback did not restore previous config: props=%q bukkit=%q", gotProps, gotBukkit)
	}
}

func TestScheduledPruneMovesOnlyAutomationOwnedBackupsToTrash(t *testing.T) {
	s, cleanup := setupBackupPolicyTest(t)
	defer cleanup()

	auto, err := createBackupWithReason(s, "config", false, "automation:test-nightly")
	if err != nil {
		t.Fatal(err)
	}
	autoPath, err := safeBackupPath(s, auto.File)
	if err != nil {
		t.Fatal(err)
	}
	root := backupBase(s.ID, false)
	for i := 1; i <= 4; i++ {
		copyTestBackup(t, autoPath, filepath.Join(root, fmt.Sprintf("auto-copy-%d.zip", i)))
	}
	_ = os.Remove(autoPath)
	_ = os.Remove(autoPath + ".sha256")

	manual, err := createBackupWithReason(s, "config", false, "manual-test")
	if err != nil {
		t.Fatal(err)
	}
	pruneScheduledBackups(s.ID, 1)

	if _, err = safeBackupPath(s, manual.File); err != nil {
		t.Fatalf("manual backup was pruned: %v", err)
	}
	activeAuto := 0
	for _, b := range listBackups(s) {
		if strings.HasPrefix(b.SourceReason, "automation:") {
			activeAuto++
		}
	}
	if activeAuto != 1 {
		t.Fatalf("expected exactly one active automation backup, got %d", activeAuto)
	}
	trashedAuto := 0
	for _, b := range listTrashedBackups(s) {
		if strings.HasPrefix(b.SourceReason, "automation:") {
			trashedAuto++
		}
	}
	if trashedAuto != 3 {
		t.Fatalf("expected three automation backups in trash, got %d", trashedAuto)
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
