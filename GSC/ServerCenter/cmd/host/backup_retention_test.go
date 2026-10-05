package main

import (
	"os"
	"path/filepath"
	"testing"
)

func setupBackupPolicyTest(t *testing.T) (ServerConfig, func()) {
	t.Helper()
	root := t.TempDir()
	serverDir := filepath.Join(root, "server")
	if err := os.MkdirAll(serverDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "server.properties"), []byte("server-port=65530\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(serverDir, "bukkit.yml"), []byte("settings: {}\n"), 0644); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	oldConfigPath := configPath
	cfg = Config{Servers: []ServerConfig{{ID: "test", Name: "Test", Path: serverDir, JavaPort: 65530}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()

	cleanup := func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldConfigPath
		configMu.Unlock()
	}
	s, ok := serverByID("test")
	if !ok {
		cleanup()
		t.Fatal("test server missing")
	}
	return s, cleanup
}

func copyTestBackup(t *testing.T, src, dst string) {
	t.Helper()
	b, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(dst, b, 0644); err != nil {
		t.Fatal(err)
	}
	if sum, err := fileSHA256(dst); err == nil {
		_ = os.WriteFile(dst+".sha256", []byte(sum+"  "+filepath.Base(dst)+"\n"), 0644)
	} else {
		t.Fatal(err)
	}
}

func TestDay11BackupRetentionDryRunKeepsProtectedAndNewest(t *testing.T) {
	s, cleanup := setupBackupPolicyTest(t)
	defer cleanup()

	bi, err := createBackup(s, "config", false)
	if err != nil {
		t.Fatal(err)
	}
	src, err := safeBackupPath(s, bi.File)
	if err != nil {
		t.Fatal(err)
	}
	root := backupBase(s.ID, false)
	for i := 1; i <= 4; i++ {
		dst := filepath.Join(root, "test-config-backup-copy-"+string(rune('0'+i))+".zip")
		copyTestBackup(t, src, dst)
	}
	_ = os.Remove(src)
	_ = os.Remove(src + ".sha256")

	protected := filepath.Join(root, "test-config-backup-copy-1.zip")
	meta := readBackupMeta(protected)
	meta.Protected = true
	meta.ProtectedAt = "2026-10-05T00:00:00Z"
	if err = writeBackupMeta(protected, meta); err != nil {
		t.Fatal(err)
	}

	plan := buildBackupRetentionDryRun(s, 2)
	if !plan.DryRun || plan.KeepLatest != 2 {
		t.Fatalf("unexpected plan flags: %+v", plan)
	}
	if len(plan.Candidates) != 1 {
		t.Fatalf("expected 1 deletion candidate after protected + newest two, got %d: %+v", len(plan.Candidates), plan)
	}
	if plan.ReclaimBytes <= 0 {
		t.Fatalf("expected reclaim bytes, got %d", plan.ReclaimBytes)
	}
	for _, b := range plan.Candidates {
		if b.Protected || b.Kind == "checkpoint" {
			t.Fatalf("protected/checkpoint backup became retention candidate: %+v", b)
		}
	}
}

func TestDay11BackupRetentionAndDeleteBlockedByPendingUpdate(t *testing.T) {
	s, cleanup := setupBackupPolicyTest(t)
	defer cleanup()

	bi, err := createBackup(s, "config", false)
	if err != nil {
		t.Fatal(err)
	}
	tx := &updateTransaction{
		Schema: day9TransactionSchema,
		ID: "day11-retention-pending",
		ServerID: s.ID,
		Channel: "canary",
		Release: "test-release",
		Phase: "applied_pending_health",
		Created: "2026-10-05T00:00:00Z",
	}
	if err = day9PersistTransaction(s, tx, true); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = day9ClearPending(s) }()

	plan := buildBackupRetentionDryRun(s, 1)
	if plan.BlockedReason == "" || len(plan.Candidates) != 0 {
		t.Fatalf("pending transaction should block retention candidates: %+v", plan)
	}

	w := postBackupActionForTest(t, s.ID, bi.File, "trash")
	if w.Code != 409 {
		t.Fatalf("pending transaction must block backup trash: %d %s", w.Code, w.Body.String())
	}
	if _, err = safeBackupPath(s, bi.File); err != nil {
		t.Fatalf("blocked deletion changed backup: %v", err)
	}
}

func TestDay11BackupDiskGuard(t *testing.T) {
	const gib = int64(1 << 30)
	if err := backupDiskGuardForFree(10*gib, 12*gib); err != nil {
		t.Fatalf("expected enough space: %v", err)
	}
	if err := backupDiskGuardForFree(10*gib, 10*gib); err == nil {
		t.Fatal("expected disk guard to reject insufficient margin")
	}
	if err := backupDiskGuardForFree(10*gib, 0); err != nil {
		t.Fatalf("unknown free space should not create a false blocker: %v", err)
	}
}
