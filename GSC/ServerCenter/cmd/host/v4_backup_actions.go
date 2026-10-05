package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type backupMeta struct {
	Protected    bool   `json:"protected"`
	ProtectedAt  string `json:"protected_at,omitempty"`
	OriginalKind string `json:"original_kind,omitempty"`
	DeletedAt    string `json:"deleted_at,omitempty"`
}

func backupMetaPath(p string) string { return p + ".gscmeta.json" }

func readBackupMeta(p string) backupMeta {
	var m backupMeta
	b, err := os.ReadFile(backupMetaPath(p))
	if err != nil {
		return m
	}
	_ = json.Unmarshal(b, &m)
	return m
}

func writeBackupMeta(p string, m backupMeta) error {
	path := backupMetaPath(p)
	if !m.Protected && m.ProtectedAt == "" && m.OriginalKind == "" && m.DeletedAt == "" {
		_ = os.Remove(path)
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	tmp := path + ".tmp"
	if err = os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	_ = os.Remove(path)
	if err = os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func backupKindFromPath(s ServerConfig, p string) string {
	cp := filepath.Clean(p)
	if strings.EqualFold(filepath.Clean(filepath.Dir(cp)), filepath.Clean(backupBase(s.ID, true))) {
		return "checkpoint"
	}
	return "backup"
}

func backupTrashBase(serverID, kind string) string {
	if kind != "checkpoint" {
		kind = "backup"
	}
	return filepath.Join(v4Root(), "Trash", serverID, kind)
}

func safeTrashBackupPath(s ServerConfig, file string) (string, string, error) {
	name := filepath.Base(strings.TrimSpace(file))
	if name == "." || name == "" {
		return "", "", fmt.Errorf("invalid backup file")
	}
	for _, kind := range []string{"backup", "checkpoint"} {
		p := filepath.Join(backupTrashBase(s.ID, kind), name)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p, kind, nil
		}
	}
	return "", "", fmt.Errorf("trashed backup not found")
}

func moveBackupBundle(src, dst string) error {
	if _, err := os.Stat(dst); err == nil {
		return fmt.Errorf("destination already exists")
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	rollback := func() {
		_ = os.Rename(dst+".sha256", src+".sha256")
		_ = os.Rename(dst, src)
	}
	if _, err := os.Stat(src + ".sha256"); err == nil {
		if err = os.Rename(src+".sha256", dst+".sha256"); err != nil {
			rollback()
			return err
		}
	}
	return nil
}

func backupInfoAt(p, kind string, trashed bool) (BackupInfo, error) {
	m, err := readBackupManifest(p)
	if err != nil {
		return BackupInfo{}, err
	}
	st, err := os.Stat(p)
	if err != nil {
		return BackupInfo{}, err
	}
	sha := ""
	if b, e := os.ReadFile(p + ".sha256"); e == nil {
		f := strings.Fields(string(b))
		if len(f) > 0 {
			sha = f[0]
		}
	}
	meta := readBackupMeta(p)
	return BackupInfo{
		File: filepath.Base(p), Path: p, Scope: m.Scope, Created: m.Created,
		Size: st.Size(), Verified: sha != "", SHA256: sha,
		Kind: kind, Protected: meta.Protected, Trashed: trashed,
	}, nil
}

func listTrashedBackups(s ServerConfig) []BackupInfo {
	out := []BackupInfo{}
	for _, kind := range []string{"backup", "checkpoint"} {
		root := backupTrashBase(s.ID, kind)
		es, _ := os.ReadDir(root)
		for _, e := range es {
			if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".zip") {
				continue
			}
			if bi, err := backupInfoAt(filepath.Join(root, e.Name()), kind, true); err == nil {
				out = append(out, bi)
			}
		}
	}
	sortBackupInfos(out)
	return out
}

func sortBackupInfos(out []BackupInfo) {
	sort.Slice(out, func(i, j int) bool { return out[i].Created > out[j].Created })
}

type BackupRetentionDryRun struct {
	ServerID      string       `json:"server_id"`
	DryRun        bool         `json:"dry_run"`
	KeepLatest    int          `json:"keep_latest"`
	Total         int          `json:"total"`
	Kept          []BackupInfo `json:"kept"`
	Candidates    []BackupInfo `json:"candidates"`
	ReclaimBytes  int64        `json:"reclaim_bytes"`
	BlockedReason string       `json:"blocked_reason,omitempty"`
}

func buildBackupRetentionDryRun(s ServerConfig, keepLatest int) BackupRetentionDryRun {
	if keepLatest < 1 {
		keepLatest = 2
	}
	if keepLatest > 100 {
		keepLatest = 100
	}
	all := listBackups(s)
	out := BackupRetentionDryRun{
		ServerID: s.ID,
		DryRun: true,
		KeepLatest: keepLatest,
		Total: len(all),
		Kept: []BackupInfo{},
		Candidates: []BackupInfo{},
	}
	if hasPendingUpdate(s) {
		out.Kept = append(out.Kept, all...)
		out.BlockedReason = "pending update transaction: retention deletion is blocked"
		return out
	}
	regularKept := 0
	for _, b := range all {
		if b.Protected || b.Kind == "checkpoint" {
			out.Kept = append(out.Kept, b)
			continue
		}
		if regularKept < keepLatest {
			regularKept++
			out.Kept = append(out.Kept, b)
			continue
		}
		out.Candidates = append(out.Candidates, b)
		out.ReclaimBytes += b.Size
	}
	return out
}

func apiV4BackupRetentionDryRun(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID         string `json:"id"`
		KeepLatest int    `json:"keep_latest"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	s, ok := serverByID(strings.TrimSpace(q.ID))
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	writeJSON(w, buildBackupRetentionDryRun(s, q.KeepLatest))
}

type BackupRetentionApplyResult struct {
	ServerID     string       `json:"server_id"`
	DryRun       bool         `json:"dry_run"`
	KeepLatest   int          `json:"keep_latest"`
	Moved        []BackupInfo `json:"moved"`
	ReclaimBytes int64        `json:"reclaim_bytes"`
}

func trashBackupFile(s ServerConfig, file string) (BackupInfo, error) {
	if hasPendingUpdate(s) {
		return BackupInfo{}, fmt.Errorf("pending update transaction: backup deletion is blocked until recovery/commit completes")
	}
	p, err := safeBackupPath(s, file)
	if err != nil {
		return BackupInfo{}, err
	}
	meta := readBackupMeta(p)
	if meta.Protected {
		return BackupInfo{}, fmt.Errorf("protected backup: unprotect before moving to trash")
	}
	kind := backupKindFromPath(s, p)
	dst := filepath.Join(backupTrashBase(s.ID, kind), filepath.Base(p))
	if err = moveBackupBundle(p, dst); err != nil {
		return BackupInfo{}, err
	}
	meta.OriginalKind = kind
	meta.DeletedAt = time.Now().Format(time.RFC3339)
	if err = writeBackupMeta(dst, meta); err != nil {
		_ = os.Rename(dst+".sha256", p+".sha256")
		_ = os.Rename(dst, p)
		return BackupInfo{}, fmt.Errorf("trash metadata write failed; backup restored to original location: %w", err)
	}
	_ = os.Remove(backupMetaPath(p))
	return backupInfoAt(dst, kind, true)
}

func restoreTrashedBackupFile(s ServerConfig, file string) (BackupInfo, error) {
	p, kind, err := safeTrashBackupPath(s, file)
	if err != nil {
		return BackupInfo{}, err
	}
	meta := readBackupMeta(p)
	if meta.OriginalKind == "backup" || meta.OriginalKind == "checkpoint" {
		kind = meta.OriginalKind
	}
	dst := filepath.Join(backupBase(s.ID, kind == "checkpoint"), filepath.Base(p))
	if err = moveBackupBundle(p, dst); err != nil {
		return BackupInfo{}, err
	}
	meta.DeletedAt = ""
	meta.OriginalKind = ""
	if err = writeBackupMeta(dst, meta); err != nil {
		_ = os.Rename(dst+".sha256", p+".sha256")
		_ = os.Rename(dst, p)
		return BackupInfo{}, fmt.Errorf("restore metadata write failed; backup returned to trash: %w", err)
	}
	_ = os.Remove(backupMetaPath(p))
	return backupInfoAt(dst, kind, false)
}

func applyBackupRetentionToTrash(s ServerConfig, keepLatest int) (BackupRetentionApplyResult, error) {
	plan := buildBackupRetentionDryRun(s, keepLatest)
	out := BackupRetentionApplyResult{
		ServerID: s.ID,
		DryRun: false,
		KeepLatest: plan.KeepLatest,
		Moved: []BackupInfo{},
	}
	if plan.BlockedReason != "" {
		return out, fmt.Errorf("%s", plan.BlockedReason)
	}
	for _, candidate := range plan.Candidates {
		moved, err := trashBackupFile(s, candidate.File)
		if err != nil {
			// Retention is all-or-nothing. Restore every candidate already moved
			// during this request before returning an error.
			for i := len(out.Moved) - 1; i >= 0; i-- {
				_, _ = restoreTrashedBackupFile(s, out.Moved[i].File)
			}
			out.Moved = nil
			out.ReclaimBytes = 0
			return out, err
		}
		out.Moved = append(out.Moved, moved)
		out.ReclaimBytes += moved.Size
	}
	return out, nil
}

func apiV4BackupRetentionApply(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID         string `json:"id"`
		KeepLatest int    `json:"keep_latest"`
		Confirm    string `json:"confirm"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if q.Confirm != "MOVE_TO_TRASH" {
		http.Error(w, "confirm must be MOVE_TO_TRASH", http.StatusBadRequest)
		return
	}
	s, ok := serverByID(strings.TrimSpace(q.ID))
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	rel, err := beginV4Operation(s.ID, "backup-retention:apply")
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	defer rel()
	result, err := applyBackupRetentionToTrash(s, q.KeepLatest)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	appendV4Event("warn", "backup", s.ID, "백업 retention 휴지통 이동",
		fmt.Sprintf("moved=%d reclaim_bytes=%d keep_latest=%d", len(result.Moved), result.ReclaimBytes, result.KeepLatest))
	appendAudit(r, "backup.retention.apply", s.ID, "completed",
		fmt.Sprintf("moved=%d reclaim_bytes=%d keep_latest=%d", len(result.Moved), result.ReclaimBytes, result.KeepLatest))
	writeJSON(w, result)
}

func apiV4BackupTrash(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	s, ok := serverByID(strings.TrimSpace(r.URL.Query().Get("id")))
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	items := listTrashedBackups(s)
	var total int64
	for _, b := range items {
		total += b.Size
	}
	writeJSON(w, map[string]any{"backups": items, "trash_bytes": total})
}

func apiV4BackupAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID     string `json:"id"`
		File   string `json:"file"`
		Action string `json:"action"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	s, ok := serverByID(strings.TrimSpace(q.ID))
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	q.Action = strings.ToLower(strings.TrimSpace(q.Action))
	if q.Action != "protect" && q.Action != "unprotect" && q.Action != "trash" && q.Action != "restore-trash" && q.Action != "delete-permanent" {
		http.Error(w, "unsupported backup action", http.StatusBadRequest)
		return
	}
	rel, err := beginV4Operation(s.ID, "backup-action:"+q.Action)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	defer rel()

	if (q.Action == "trash" || q.Action == "delete-permanent") && hasPendingUpdate(s) {
		http.Error(w, "pending update transaction: backup deletion is blocked until recovery/commit completes", http.StatusConflict)
		return
	}

	switch q.Action {
	case "protect", "unprotect":
		p, err := safeBackupPath(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		meta := readBackupMeta(p)
		meta.Protected = q.Action == "protect"
		if meta.Protected {
			meta.ProtectedAt = time.Now().Format(time.RFC3339)
		} else {
			meta.ProtectedAt = ""
		}
		if err = writeBackupMeta(p, meta); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		appendV4Event("info", "backup", s.ID, map[bool]string{true: "백업 보호 지정", false: "백업 보호 해제"}[meta.Protected]+": "+filepath.Base(p), "")
		appendAudit(r, "backup."+q.Action, s.ID+":"+filepath.Base(p), "completed", "")
		writeJSON(w, map[string]any{"ok": true, "protected": meta.Protected})
		return

	case "trash":
		moved, err := trashBackupFile(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		appendV4Event("warn", "backup", s.ID, "백업 휴지통 이동: "+moved.File, "kind="+moved.Kind)
		appendAudit(r, "backup.trash", s.ID+":"+moved.File, "completed", moved.Kind)
		writeJSON(w, map[string]any{"ok": true, "trashed": true})
		return

	case "restore-trash":
		restored, err := restoreTrashedBackupFile(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		appendV4Event("info", "backup", s.ID, "휴지통 백업 복구: "+restored.File, "kind="+restored.Kind)
		appendAudit(r, "backup.restore-trash", s.ID+":"+restored.File, "completed", restored.Kind)
		writeJSON(w, map[string]any{"ok": true, "trashed": false})
		return

	case "delete-permanent":
		p, _, err := safeTrashBackupPath(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		meta := readBackupMeta(p)
		if meta.Protected {
			http.Error(w, "protected backup cannot be permanently deleted", http.StatusConflict)
			return
		}
		if err = os.Remove(p); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		_ = os.Remove(p + ".sha256")
		_ = os.Remove(backupMetaPath(p))
		appendV4Event("warn", "backup", s.ID, "백업 영구 삭제: "+filepath.Base(p), "")
		appendAudit(r, "backup.delete-permanent", s.ID+":"+filepath.Base(p), "completed", "")
		writeJSON(w, map[string]any{"ok": true, "deleted": true})
		return
	}
}
