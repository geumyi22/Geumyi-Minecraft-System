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
		p, err := safeBackupPath(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		meta := readBackupMeta(p)
		if meta.Protected {
			http.Error(w, "protected backup: unprotect before moving to trash", http.StatusConflict)
			return
		}
		kind := backupKindFromPath(s, p)
		dst := filepath.Join(backupTrashBase(s.ID, kind), filepath.Base(p))
		if err = moveBackupBundle(p, dst); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		meta.OriginalKind = kind
		meta.DeletedAt = time.Now().Format(time.RFC3339)
		if err = writeBackupMeta(dst, meta); err != nil {
			_ = os.Rename(dst+".sha256", p+".sha256")
			_ = os.Rename(dst, p)
			http.Error(w, "trash metadata write failed; backup restored to original location: "+err.Error(), http.StatusInternalServerError)
			return
		}
		_ = os.Remove(backupMetaPath(p))
		appendV4Event("warn", "backup", s.ID, "백업 휴지통 이동: "+filepath.Base(dst), "kind="+kind)
		appendAudit(r, "backup.trash", s.ID+":"+filepath.Base(dst), "completed", kind)
		writeJSON(w, map[string]any{"ok": true, "trashed": true})
		return

	case "restore-trash":
		p, kind, err := safeTrashBackupPath(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		meta := readBackupMeta(p)
		if meta.OriginalKind == "backup" || meta.OriginalKind == "checkpoint" {
			kind = meta.OriginalKind
		}
		dst := filepath.Join(backupBase(s.ID, kind == "checkpoint"), filepath.Base(p))
		if err = moveBackupBundle(p, dst); err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		meta.DeletedAt = ""
		meta.OriginalKind = ""
		if err = writeBackupMeta(dst, meta); err != nil {
			_ = os.Rename(dst+".sha256", p+".sha256")
			_ = os.Rename(dst, p)
			http.Error(w, "restore metadata write failed; backup returned to trash: "+err.Error(), http.StatusInternalServerError)
			return
		}
		_ = os.Remove(backupMetaPath(p))
		appendV4Event("info", "backup", s.ID, "휴지통 백업 복구: "+filepath.Base(dst), "kind="+kind)
		appendAudit(r, "backup.restore-trash", s.ID+":"+filepath.Base(dst), "completed", kind)
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
