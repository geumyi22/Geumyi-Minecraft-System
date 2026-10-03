package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeTestBackup(t *testing.T, root, serverID, scope, kind, name string) string {
	t.Helper()
	if err := os.MkdirAll(root, 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, name)
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	manifest := BackupManifest{
		Format: 1, GSCVersion: appVersion, ServerID: serverID, ServerName: "Test",
		Scope: scope, Created: time.Now().Format(time.RFC3339), Roots: []string{"world"},
	}
	b, _ := json.Marshal(manifest)
	w, err := zw.Create("GSC_BACKUP_MANIFEST.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = w.Write(b); err != nil {
		t.Fatal(err)
	}
	w, err = zw.Create("world/level.dat")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = w.Write([]byte("test")); err != nil {
		t.Fatal(err)
	}
	if err = zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err = f.Close(); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(body)
	sha := hex.EncodeToString(sum[:])
	if err = os.WriteFile(path+".sha256", []byte(sha+"  "+filepath.Base(path)+"\r\n"), 0644); err != nil {
		t.Fatal(err)
	}
	_ = kind
	return path
}

func withBackupTestRoot(t *testing.T) ServerConfig {
	t.Helper()
	configMu.Lock()
	oldPath := configPath
	oldCfg := cfg
	root := t.TempDir()
	configPath = filepath.Join(root, "server.json")
	cfg = Config{Servers: []ServerConfig{{ID: "wild", Name: "Wild", Role: serverRoleWild}}}
	configMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		configPath = oldPath
		cfg = oldCfg
		configMu.Unlock()
	})
	return ServerConfig{ID: "wild", Name: "Wild", Role: serverRoleWild}
}

func TestProtectedBackupCannotBeTrashedUntilUnprotected(t *testing.T) {
	s := withBackupTestRoot(t)
	path := writeTestBackup(t, backupBase(s.ID, false), s.ID, "world", "backup", "wild-world-backup-test.zip")
	if err := setBackupProtected(path, true); err != nil {
		t.Fatal(err)
	}
	if _, err := trashBackup(s, filepath.Base(path)); err == nil {
		t.Fatal("protected backup must not move to trash")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("protected backup moved unexpectedly: %v", err)
	}

	if err := setBackupProtected(path, false); err != nil {
		t.Fatal(err)
	}
	info, err := trashBackup(s, filepath.Base(path))
	if err != nil {
		t.Fatal(err)
	}
	if !info.Trashed || info.Kind != "backup" {
		t.Fatalf("unexpected trash info: %+v", info)
	}
	if _, err = os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("active path should be gone after trash, err=%v", err)
	}
	if _, err = os.Stat(filepath.Join(backupTrashBase(s.ID), filepath.Base(path))); err != nil {
		t.Fatalf("trash file missing: %v", err)
	}
}

func TestTrashRestoreRoundTripPreservesCheckpointProtection(t *testing.T) {
	s := withBackupTestRoot(t)
	path := writeTestBackup(t, backupBase(s.ID, true), s.ID, "config", "checkpoint", "wild-config-checkpoint-test.zip")
	if err := setBackupProtected(path, true); err != nil {
		t.Fatal(err)
	}
	if err := setBackupProtected(path, false); err != nil {
		t.Fatal(err)
	}
	trashed, err := trashBackup(s, filepath.Base(path))
	if err != nil {
		t.Fatal(err)
	}
	if trashed.Kind != "checkpoint" {
		t.Fatalf("kind=%q want checkpoint", trashed.Kind)
	}
	restored, err := restoreTrashedBackup(s, filepath.Base(path))
	if err != nil {
		t.Fatal(err)
	}
	if restored.Kind != "checkpoint" || restored.Trashed {
		t.Fatalf("unexpected restored info: %+v", restored)
	}
	if filepath.Dir(restored.Path) != filepath.Clean(backupBase(s.ID, true)) {
		t.Fatalf("restored checkpoint to wrong root: %s", restored.Path)
	}
}

func TestPermanentDeleteOnlyAcceptsTrash(t *testing.T) {
	s := withBackupTestRoot(t)
	path := writeTestBackup(t, backupBase(s.ID, false), s.ID, "world", "backup", "wild-world-backup-delete.zip")
	if err := permanentlyDeleteTrashedBackup(s, filepath.Base(path)); err == nil {
		t.Fatal("must not permanently delete an active backup directly")
	}
	if _, err := trashBackup(s, filepath.Base(path)); err != nil {
		t.Fatal(err)
	}
	if err := permanentlyDeleteTrashedBackup(s, filepath.Base(path)); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{
		filepath.Join(backupTrashBase(s.ID), filepath.Base(path)),
		filepath.Join(backupTrashBase(s.ID), filepath.Base(path)) + ".sha256",
		backupTrashMetadataPath(filepath.Join(backupTrashBase(s.ID), filepath.Base(path))),
	} {
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Fatalf("trash artifact still exists: %s err=%v", p, err)
		}
	}
}

func TestListBackupsSeparatesActiveAndTrash(t *testing.T) {
	s := withBackupTestRoot(t)
	activePath := writeTestBackup(t, backupBase(s.ID, false), s.ID, "world", "backup", "wild-active.zip")
	trashPath := writeTestBackup(t, backupBase(s.ID, false), s.ID, "config", "backup", "wild-trash.zip")
	if err := setBackupProtected(activePath, true); err != nil {
		t.Fatal(err)
	}
	if _, err := trashBackup(s, filepath.Base(trashPath)); err != nil {
		t.Fatal(err)
	}
	active, trash := listBackups(s)
	if len(active) != 1 || len(trash) != 1 {
		t.Fatalf("active=%d trash=%d", len(active), len(trash))
	}
	if !active[0].Protected || active[0].Trashed {
		t.Fatalf("active metadata wrong: %+v", active[0])
	}
	if !trash[0].Trashed || trash[0].TrashedAt == "" {
		t.Fatalf("trash metadata wrong: %+v", trash[0])
	}
}
