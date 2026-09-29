package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const day9TransactionSchema = 1

type updateTransactionItem struct {
	Key          string `json:"key"`
	PluginName   string `json:"plugin_name"`
	FromVersion  string `json:"from_version"`
	ToVersion    string `json:"to_version"`
	OldFile      string `json:"old_file"`
	NewFile      string `json:"new_file"`
	Backup       string `json:"backup"`
	Stage        string `json:"stage"`
	BackupSHA256 string `json:"backup_sha256"`
	NewSHA256    string `json:"new_sha256"`
}

type updateTransaction struct {
	Schema         int                     `json:"schema"`
	ID             string                  `json:"id"`
	ServerID       string                  `json:"server_id"`
	Channel        string                  `json:"channel"`
	Release        string                  `json:"release"`
	ManifestSHA256 string                  `json:"manifest_sha256"`
	Phase          string                  `json:"phase"`
	Reason         string                  `json:"reason,omitempty"`
	Created        string                  `json:"created"`
	Updated        string                  `json:"updated"`
	Items          []updateTransactionItem `json:"items"`
}

type rejectedUpdateRelease struct {
	ServerID string `json:"server_id"`
	Release  string `json:"release"`
	Reason   string `json:"reason"`
	Updated  string `json:"updated"`
}

// Tests may inject a deterministic failure at transaction boundaries.
// Production leaves this nil.
var day9UpdateFaultHook func(string) error

func day9UpdateRoot(s ServerConfig) string {
	return filepath.Join(resolveServerDir(s), ".geumyi-update")
}

func day9PendingPath(s ServerConfig) string {
	return filepath.Join(day9UpdateRoot(s), "pending.json")
}

func day9RejectedPath(s ServerConfig) string {
	return filepath.Join(day9UpdateRoot(s), "rejected-release.json")
}

func day9MaybeFault(point string) error {
	if day9UpdateFaultHook != nil {
		return day9UpdateFaultHook(point)
	}
	return nil
}

func day9WriteJSONAtomic(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	_ = os.Remove(path)
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func day9AppendJournal(s ServerConfig, tx *updateTransaction, event, detail string) {
	if tx == nil {
		return
	}
	root := day9UpdateRoot(s)
	_ = os.MkdirAll(root, 0755)
	entry := map[string]any{
		"time":       time.Now().Format(time.RFC3339Nano),
		"transaction": tx.ID,
		"server_id":  tx.ServerID,
		"release":    tx.Release,
		"phase":      tx.Phase,
		"event":      event,
		"detail":     detail,
	}
	b, err := json.Marshal(entry)
	if err != nil {
		return
	}
	f, err := os.OpenFile(filepath.Join(root, "journal.jsonl"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(b, '\n'))
}

func day9TransactionFile(s ServerConfig, id string) string {
	return filepath.Join(day9UpdateRoot(s), "transactions", safePathPart(id), "transaction.json")
}

func day9PersistTransaction(s ServerConfig, tx *updateTransaction, pending bool) error {
	if tx == nil {
		return errors.New("nil update transaction")
	}
	tx.Updated = time.Now().Format(time.RFC3339Nano)
	if err := day9WriteJSONAtomic(day9TransactionFile(s, tx.ID), tx); err != nil {
		return err
	}
	if pending {
		if err := day9WriteJSONAtomic(day9PendingPath(s), tx); err != nil {
			return err
		}
	}
	return nil
}

func day9LoadPendingTransaction(s ServerConfig) (*updateTransaction, error) {
	b, err := os.ReadFile(day9PendingPath(s))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var tx updateTransaction
	if err := json.Unmarshal(b, &tx); err != nil {
		return nil, fmt.Errorf("pending transaction JSON 오류: %w", err)
	}
	if tx.Schema != day9TransactionSchema || tx.ServerID != s.ID || tx.ID == "" {
		return nil, errors.New("pending transaction metadata mismatch")
	}
	return &tx, nil
}

func hasPendingUpdate(s ServerConfig) bool {
	tx, err := day9LoadPendingTransaction(s)
	return err == nil && tx != nil
}

func day9ClearPending(s ServerConfig) error {
	err := os.Remove(day9PendingPath(s))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func day9FileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func prepareUpdateTransaction(s ServerConfig, plan []updatePlanItem, cachePaths map[string]string, channel, release, manifestHash string) (*updateTransaction, error) {
	if len(plan) == 0 {
		return nil, errors.New("empty update plan")
	}
	root := day9UpdateRoot(s)
	id := time.Now().UTC().Format("20060102T150405.000000000Z") + "-" + safePathPart(release)
	txDir := filepath.Join(root, "transactions", safePathPart(id))
	backupDir := filepath.Join(txDir, "backup")
	stageDir := filepath.Join(txDir, "staging")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(stageDir, 0755); err != nil {
		return nil, err
	}

	tx := &updateTransaction{
		Schema:         day9TransactionSchema,
		ID:             id,
		ServerID:       s.ID,
		Channel:        channel,
		Release:        release,
		ManifestSHA256: manifestHash,
		Phase:          "preparing",
		Created:        time.Now().Format(time.RFC3339Nano),
	}
	pluginDir := filepath.Join(resolveServerDir(s), "plugins")
	for i, item := range plan {
		cachePath := cachePaths[item.Key]
		if cachePath == "" {
			_ = os.RemoveAll(txDir)
			return nil, fmt.Errorf("%s cache path missing", item.Component.PluginName)
		}
		oldName := filepath.Base(item.Installed.File)
		newName := filepath.Base(item.Component.File)
		if oldName != item.Installed.File || newName != item.Component.File {
			_ = os.RemoveAll(txDir)
			return nil, fmt.Errorf("%s unsafe plugin file name", item.Component.PluginName)
		}
		oldPath := filepath.Join(pluginDir, oldName)
		newPath := filepath.Join(pluginDir, newName)
		if filepath.Clean(oldPath) != filepath.Clean(newPath) {
			if _, err := os.Stat(newPath); err == nil {
				_ = os.RemoveAll(txDir)
				return nil, fmt.Errorf("target JAR already exists: %s", newName)
			} else if !errors.Is(err, os.ErrNotExist) {
				_ = os.RemoveAll(txDir)
				return nil, err
			}
		}
		oldHash, err := day9FileSHA256(oldPath)
		if err != nil {
			_ = os.RemoveAll(txDir)
			return nil, fmt.Errorf("%s current JAR hash failed: %w", item.Component.PluginName, err)
		}

		backupName := fmt.Sprintf("%02d-%s", i, oldName)
		stageName := fmt.Sprintf("%02d-%s", i, newName)
		backup := filepath.Join(backupDir, backupName)
		stage := filepath.Join(stageDir, stageName)
		if err := copyFileV4(oldPath, backup); err != nil {
			_ = os.RemoveAll(txDir)
			return nil, fmt.Errorf("%s backup failed: %w", item.Component.PluginName, err)
		}
		backupHash, err := day9FileSHA256(backup)
		if err != nil || !strings.EqualFold(backupHash, oldHash) {
			_ = os.RemoveAll(txDir)
			if err != nil {
				return nil, fmt.Errorf("%s backup verification failed: %w", item.Component.PluginName, err)
			}
			return nil, fmt.Errorf("%s backup verification failed", item.Component.PluginName)
		}
		if err := copyFileV4(cachePath, stage); err != nil {
			_ = os.RemoveAll(txDir)
			return nil, fmt.Errorf("%s staging failed: %w", item.Component.PluginName, err)
		}
		ok, err := verifyArtifactFile(stage, item.Component)
		if err != nil || !ok {
			_ = os.RemoveAll(txDir)
			if err != nil {
				return nil, fmt.Errorf("%s staged verification failed: %w", item.Component.PluginName, err)
			}
			return nil, fmt.Errorf("%s staged verification failed", item.Component.PluginName)
		}
		tx.Items = append(tx.Items, updateTransactionItem{
			Key:          item.Key,
			PluginName:   item.Component.PluginName,
			FromVersion:  item.Installed.Version,
			ToVersion:    item.Component.Version,
			OldFile:      oldName,
			NewFile:      newName,
			Backup:       filepath.ToSlash(filepath.Join("transactions", safePathPart(id), "backup", backupName)),
			Stage:        filepath.ToSlash(filepath.Join("transactions", safePathPart(id), "staging", stageName)),
			BackupSHA256: oldHash,
			NewSHA256:    item.Component.SHA256,
		})
	}
	if err := day9MaybeFault("after_prepare"); err != nil {
		_ = os.RemoveAll(txDir)
		return nil, err
	}
	tx.Phase = "prepared"
	if err := day9PersistTransaction(s, tx, true); err != nil {
		_ = os.RemoveAll(txDir)
		return nil, err
	}
	day9AppendJournal(s, tx, "prepared", fmt.Sprintf("%d component(s) backed up and staged", len(tx.Items)))
	return tx, nil
}

func day9RestoreTransactionFiles(s ServerConfig, tx *updateTransaction) error {
	if tx == nil {
		return errors.New("nil update transaction")
	}
	root := day9UpdateRoot(s)
	pluginDir := filepath.Join(resolveServerDir(s), "plugins")
	var failures []string
	for i := len(tx.Items) - 1; i >= 0; i-- {
		item := tx.Items[i]
		backup := filepath.Join(root, filepath.FromSlash(item.Backup))
		backupHash, err := day9FileSHA256(backup)
		if err != nil || !strings.EqualFold(backupHash, item.BackupSHA256) {
			if err != nil {
				failures = append(failures, item.PluginName+": backup unreadable: "+err.Error())
			} else {
				failures = append(failures, item.PluginName+": backup SHA-256 mismatch")
			}
			continue
		}
		oldPath := filepath.Join(pluginDir, item.OldFile)
		newPath := filepath.Join(pluginDir, item.NewFile)
		if filepath.Clean(newPath) != filepath.Clean(oldPath) {
			_ = os.Remove(newPath)
		}
		currentHash, _ := day9FileSHA256(oldPath)
		if strings.EqualFold(currentHash, item.BackupSHA256) {
			continue
		}
		_ = os.Remove(oldPath)
		if err := copyFileV4(backup, oldPath); err != nil {
			failures = append(failures, item.PluginName+": restore failed: "+err.Error())
			continue
		}
		restoredHash, err := day9FileSHA256(oldPath)
		if err != nil || !strings.EqualFold(restoredHash, item.BackupSHA256) {
			if err != nil {
				failures = append(failures, item.PluginName+": restored hash failed: "+err.Error())
			} else {
				failures = append(failures, item.PluginName+": restored SHA-256 mismatch")
			}
		}
	}
	if len(failures) > 0 {
		return errors.New(strings.Join(failures, " | "))
	}
	return nil
}

func activatePreparedUpdateTransaction(s ServerConfig, tx *updateTransaction) error {
	if tx == nil || tx.Phase != "prepared" {
		return errors.New("transaction is not prepared")
	}
	root := day9UpdateRoot(s)
	pluginDir := filepath.Join(resolveServerDir(s), "plugins")
	tx.Phase = "committing"
	if err := day9PersistTransaction(s, tx, true); err != nil {
		return err
	}
	day9AppendJournal(s, tx, "commit-start", "atomic replacement started")

	for i, item := range tx.Items {
		if err := day9MaybeFault("before_activate:" + item.Key); err != nil {
			if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
				return fmt.Errorf("failure injection: %v; rollback failed: %v", err, rb)
			}
			tx.Phase = "rolled_back"
			tx.Reason = err.Error()
			_ = day9PersistTransaction(s, tx, false)
			_ = day9ClearPending(s)
			day9AppendJournal(s, tx, "rollback", tx.Reason)
			return err
		}
		stage := filepath.Join(root, filepath.FromSlash(item.Stage))
		oldPath := filepath.Join(pluginDir, item.OldFile)
		newPath := filepath.Join(pluginDir, item.NewFile)

		if err := os.Remove(oldPath); err != nil {
			if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
				return fmt.Errorf("%s remove failed: %v; rollback failed: %v", item.PluginName, err, rb)
			}
			_ = day9ClearPending(s)
			return fmt.Errorf("%s old plugin remove failed: %w", item.PluginName, err)
		}
		if err := os.Rename(stage, newPath); err != nil {
			if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
				return fmt.Errorf("%s activate failed: %v; rollback failed: %v", item.PluginName, err, rb)
			}
			_ = day9ClearPending(s)
			return fmt.Errorf("%s new plugin activate failed: %w", item.PluginName, err)
		}
		got, err := day9FileSHA256(newPath)
		if err != nil || !strings.EqualFold(got, item.NewSHA256) {
			if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
				return fmt.Errorf("%s installed verify failed; rollback failed: %v", item.PluginName, rb)
			}
			_ = day9ClearPending(s)
			if err != nil {
				return fmt.Errorf("%s installed verify failed: %w", item.PluginName, err)
			}
			return fmt.Errorf("%s installed SHA-256 mismatch", item.PluginName)
		}
		if err := day9MaybeFault(fmt.Sprintf("after_activate:%d:%s", i, item.Key)); err != nil {
			if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
				return fmt.Errorf("failure injection: %v; rollback failed: %v", err, rb)
			}
			tx.Phase = "rolled_back"
			tx.Reason = err.Error()
			_ = day9PersistTransaction(s, tx, false)
			_ = day9ClearPending(s)
			day9AppendJournal(s, tx, "rollback", tx.Reason)
			return err
		}
	}

	tx.Phase = "applied_pending_health"
	if err := day9PersistTransaction(s, tx, true); err != nil {
		if rb := day9RestoreTransactionFiles(s, tx); rb != nil {
			return fmt.Errorf("pending-health state write failed: %v; rollback failed: %v", err, rb)
		}
		_ = day9ClearPending(s)
		return fmt.Errorf("pending-health state write failed: %w", err)
	}
	day9AppendJournal(s, tx, "applied", "files activated; waiting for post-start health gate")
	return nil
}

func applyUpdateTransaction(s ServerConfig, plan []updatePlanItem, cachePaths map[string]string, channel, release, manifestHash string) (*updateTransaction, error) {
	tx, err := prepareUpdateTransaction(s, plan, cachePaths, channel, release, manifestHash)
	if err != nil {
		return nil, err
	}
	if err := activatePreparedUpdateTransaction(s, tx); err != nil {
		return tx, err
	}
	return tx, nil
}

func day9WriteRejectedRelease(s ServerConfig, release, reason string) {
	if strings.TrimSpace(release) == "" {
		return
	}
	_ = day9WriteJSONAtomic(day9RejectedPath(s), rejectedUpdateRelease{
		ServerID: s.ID,
		Release:  release,
		Reason:   reason,
		Updated:  time.Now().Format(time.RFC3339Nano),
	})
}

func rejectedUpdateForRelease(s ServerConfig, release string) (bool, string) {
	b, err := os.ReadFile(day9RejectedPath(s))
	if err != nil {
		return false, ""
	}
	var r rejectedUpdateRelease
	if json.Unmarshal(b, &r) != nil || r.ServerID != s.ID || r.Release != release {
		return false, ""
	}
	return true, r.Reason
}

func rollbackPendingUpdate(s ServerConfig, reason string, rejectRelease bool) (*updateTransaction, error) {
	if tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) || trackedServerAlive(s.ID) {
		return nil, errors.New("rollback requires the Minecraft server to be fully offline")
	}
	tx, err := day9LoadPendingTransaction(s)
	if err != nil || tx == nil {
		if err != nil {
			return nil, err
		}
		return nil, errors.New("no pending update transaction")
	}
	tx.Phase = "rolling_back"
	tx.Reason = reason
	_ = day9PersistTransaction(s, tx, true)
	day9AppendJournal(s, tx, "rollback-start", reason)
	if err := day9RestoreTransactionFiles(s, tx); err != nil {
		tx.Phase = "rollback_failed"
		tx.Reason = reason + " | " + err.Error()
		_ = day9PersistTransaction(s, tx, true)
		day9AppendJournal(s, tx, "rollback-failed", tx.Reason)
		return tx, err
	}
	tx.Phase = "rolled_back"
	tx.Reason = reason
	if err := day9PersistTransaction(s, tx, false); err != nil {
		return tx, err
	}
	if rejectRelease {
		day9WriteRejectedRelease(s, tx.Release, reason)
	}
	if err := day9ClearPending(s); err != nil {
		return tx, err
	}
	day9AppendJournal(s, tx, "rolled-back", reason)
	return tx, nil
}

func recoverInterruptedUpdate(s ServerConfig) (bool, error) {
	tx, err := day9LoadPendingTransaction(s)
	if err != nil || tx == nil {
		return false, err
	}
	if tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) || trackedServerAlive(s.ID) {
		return false, errors.New("cannot recover update transaction while server is online")
	}
	reject := tx.Phase == "committing" || tx.Phase == "applied_pending_health" || tx.Phase == "rolling_back" || tx.Phase == "rollback_failed"
	reason := "이전 실행에서 미완료된 업데이트 트랜잭션 자동 복구"
	if _, err := rollbackPendingUpdate(s, reason, reject); err != nil {
		return false, err
	}
	appendV4Event("warn", "update", s.ID, "미완료 업데이트 자동 롤백", "transaction="+tx.ID+" release="+tx.Release)
	return true, nil
}

func markPendingUpdateHealthy(s ServerConfig) (*updateTransaction, error) {
	tx, err := day9LoadPendingTransaction(s)
	if err != nil || tx == nil {
		if err != nil {
			return nil, err
		}
		return nil, errors.New("no pending update transaction")
	}
	if tx.Phase != "applied_pending_health" {
		return nil, fmt.Errorf("unexpected pending transaction phase: %s", tx.Phase)
	}
	tx.Phase = "committed"
	tx.Reason = ""
	if err := day9PersistTransaction(s, tx, false); err != nil {
		return tx, err
	}
	if err := day9ClearPending(s); err != nil {
		return tx, err
	}
	applied := make([]string, 0, len(tx.Items))
	for _, item := range tx.Items {
		applied = append(applied, item.PluginName+" "+item.ToVersion)
	}
	st := UpdateStatus{
		ServerID:  s.ID,
		Phase:     "applied",
		Channel:   tx.Channel,
		Release:   tx.Release,
		Message:   fmt.Sprintf("%d개 업데이트 health 검증 완료", len(applied)),
		Applied:   applied,
		Updated:   time.Now().Format(time.RFC3339),
	}
	writeUpdateState(s, st, tx.ManifestSHA256)
	setUpdateStatus(st)
	day9AppendJournal(s, tx, "committed", "post-start health gate passed")
	appendV4Event("info", "update", s.ID, "업데이트 트랜잭션 확정", "transaction="+tx.ID+" release="+tx.Release)
	return tx, nil
}

func day9PostStartHealthOnce(s ServerConfig) error {
	if !tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) {
		return errors.New("Java port is not responding")
	}
	inv := pluginInventory(resolveServerDir(s))
	hasGST := false
	hasGDS := false
	for _, p := range inv {
		if !p.Enabled {
			continue
		}
		if strings.EqualFold(p.Name, "GeumyiServerTools") {
			hasGST = true
		}
		if strings.EqualFold(p.Name, "GeumyiDiscordStatus") {
			hasGDS = true
		}
	}
	if hasGST {
		gst := readGSTDiagnostics(s)
		if !gst.Available {
			return errors.New("GST diagnostics unavailable")
		}
		if gst.Stale {
			return fmt.Errorf("GST diagnostics stale (%.0fs)", gst.AgeSeconds)
		}
		if strings.EqualFold(gst.Grade, "CRITICAL") {
			return errors.New("GST health is CRITICAL")
		}
	}
	if hasGDS && s.GDSAPIPort > 0 && bridgeV4Status(s) == nil {
		return errors.New("GDS API is not responding")
	}
	return nil
}

func awaitPendingUpdateHealth(s ServerConfig, fatal func() error, timeout time.Duration) error {
	if !hasPendingUpdate(s) {
		return nil
	}
	if timeout <= 0 {
		timeout = 45 * time.Second
	}
	deadline := time.Now().Add(timeout)
	consecutive := 0
	var last error
	for time.Now().Before(deadline) {
		if fatal != nil {
			if err := fatal(); err != nil {
				return err
			}
		}
		if err := day9PostStartHealthOnce(s); err != nil {
			last = err
			consecutive = 0
		} else {
			consecutive++
			if consecutive >= 3 {
				return nil
			}
		}
		time.Sleep(time.Second)
	}
	if last == nil {
		last = errors.New("post-start health timeout")
	}
	return fmt.Errorf("post-start health gate failed: %w", last)
}

func verifyPendingUpdateAfterStart(s ServerConfig, fatal func() error) (string, error) {
	if !hasPendingUpdate(s) {
		return "", nil
	}
	st := updateStatusFor(s.ID)
	st.Phase = "health_check"
	st.Message = "업데이트 적용 후 서버 health 검증 중"
	st.Error = ""
	setUpdateStatus(st)

	if err := awaitPendingUpdateHealth(s, fatal, 45*time.Second); err == nil {
		if _, err := markPendingUpdateHealthy(s); err != nil {
			return "", fmt.Errorf("health PASS 후 transaction 확정 실패: %w", err)
		}
		return "committed", nil
	} else {
		reason := err.Error()
		st = updateStatusFor(s.ID)
		st.Phase = "rolling_back"
		st.Message = "업데이트 health 실패 · 자동 롤백 중"
		st.Error = reason
		setUpdateStatus(st)
		appendV4Event("warn", "update", s.ID, st.Message, reason)

		if _, stopErr := stopServerLocked(s); stopErr != nil {
			st.Phase = "rollback_failed"
			st.Message = "자동 롤백을 위해 서버를 정상 종료하지 못했습니다"
			st.Error = stopErr.Error()
			setUpdateStatus(st)
			return "", fmt.Errorf("%s; graceful stop failed: %w", reason, stopErr)
		}
		tx, rbErr := rollbackPendingUpdate(s, reason, true)
		if rbErr != nil {
			st.Phase = "rollback_failed"
			st.Message = "업데이트 자동 롤백 실패"
			st.Error = rbErr.Error()
			setUpdateStatus(st)
			return "", fmt.Errorf("%s; rollback failed: %w", reason, rbErr)
		}

		dir := resolveServerDir(s)
		if dir == "" {
			return "", errors.New("rollback completed but server directory unavailable")
		}
		rbProbe := newStartupLogCursor(s)
		setLaunchPhase(s.ID, "starting", "이전 정상 버전으로 재시작 중", "")
		if err := runDetachedCommand(s.StartCommand, dir, s.ID); err != nil {
			return "", fmt.Errorf("rollback completed but previous version restart failed: %w", err)
		}
		deadline := time.Now().Add(150 * time.Second)
		for time.Now().Before(deadline) {
			if failure := rbProbe.detect(); failure != nil {
				applyStartupFailure(s.ID, failure)
				return "", fmt.Errorf("rollback version startup failed: %s: %s", failure.Title, failure.Line)
			}
			if tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) {
				if err := rememberServerProcess(s); err != nil {
					return "", fmt.Errorf("rollback version process verification failed: %w", err)
				}
				st = updateStatusFor(s.ID)
				st.Phase = "rolled_back"
				st.Message = "업데이트 health 실패 · 이전 정상 버전으로 자동 복구 완료"
				st.Error = reason
				st.Applied = nil
				if tx != nil {
					st.Release = tx.Release
				}
				setUpdateStatus(st)
				appendV4Event("warn", "update", s.ID, "자동 롤백 후 서버 ONLINE", reason)
				return "rolled_back", nil
			}
			time.Sleep(500 * time.Millisecond)
		}
		return "", errors.New("rollback completed but previous version did not come online within 150 seconds")
	}
}

func day9VersionParts(v string) []int {
	v = strings.TrimSpace(v)
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		v = v[:i]
	}
	raw := strings.Split(v, ".")
	out := make([]int, len(raw))
	for i, p := range raw {
		n := 0
		for _, r := range p {
			if r < '0' || r > '9' {
				break
			}
			n = n*10 + int(r-'0')
		}
		out[i] = n
	}
	return out
}

func day9CompareVersion(a, b string) int {
	aa, bb := day9VersionParts(a), day9VersionParts(b)
	n := len(aa)
	if len(bb) > n {
		n = len(bb)
	}
	for i := 0; i < n; i++ {
		av, bv := 0, 0
		if i < len(aa) {
			av = aa[i]
		}
		if i < len(bb) {
			bv = bb[i]
		}
		if av < bv {
			return -1
		}
		if av > bv {
			return 1
		}
	}
	return 0
}

func day9VersionSatisfies(version, requirement string) bool {
	requirement = strings.TrimSpace(requirement)
	switch {
	case strings.HasPrefix(requirement, ">="):
		return day9CompareVersion(version, strings.TrimSpace(strings.TrimPrefix(requirement, ">="))) >= 0
	case strings.HasPrefix(requirement, "="):
		return day9CompareVersion(version, strings.TrimSpace(strings.TrimPrefix(requirement, "="))) == 0
	default:
		return day9CompareVersion(version, requirement) == 0
	}
}

func validateUpdatePlan(s ServerConfig, m DeploymentManifest, plan []updatePlanItem) error {
	installed := pluginInventory(resolveServerDir(s))
	installedByName := map[string][]PluginInventory{}
	for _, p := range installed {
		if p.Enabled && p.Name != "" {
			k := strings.ToLower(p.Name)
			installedByName[k] = append(installedByName[k], p)
		}
	}
	planned := map[string]updatePlanItem{}
	for _, p := range plan {
		planned[p.Key] = p
	}
	effective := map[string]string{}
	groupMembers := map[string][]string{}
	groupNeedsUpdate := map[string]bool{}

	for key, comp := range m.Components {
		if strings.ToLower(comp.Kind) != "plugin" || !targetIncludes(comp.Targets, s.ID) {
			continue
		}
		if comp.ReleaseGroup != "" {
			groupMembers[comp.ReleaseGroup] = append(groupMembers[comp.ReleaseGroup], key)
		}
		if p, ok := planned[key]; ok {
			effective[key] = p.Component.Version
			if comp.ReleaseGroup != "" {
				groupNeedsUpdate[comp.ReleaseGroup] = true
			}
			continue
		}
		cur := installedByName[strings.ToLower(comp.PluginName)]
		if len(cur) == 1 {
			effective[key] = cur[0].Version
		}
	}

	for group, members := range groupMembers {
		if !groupNeedsUpdate[group] {
			continue
		}
		for _, key := range members {
			if effective[key] == "" {
				return fmt.Errorf("release group %s is incomplete: %s is not installed", group, key)
			}
		}
	}

	for key, comp := range m.Components {
		if strings.ToLower(comp.Kind) != "plugin" || !targetIncludes(comp.Targets, s.ID) || effective[key] == "" {
			continue
		}
		for depKey, requirement := range comp.Requires {
			version := effective[depKey]
			if version == "" {
				return fmt.Errorf("%s requires %s %s, but dependency is unavailable", key, depKey, requirement)
			}
			if !day9VersionSatisfies(version, requirement) {
				return fmt.Errorf("%s requires %s %s, effective version is %s", key, depKey, requirement, version)
			}
		}
	}
	return nil
}
