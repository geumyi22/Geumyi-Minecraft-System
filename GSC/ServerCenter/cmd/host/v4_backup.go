package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
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

type BackupManifest struct {
	Format         int      `json:"format"`
	GSCVersion     string   `json:"gsc_version"`
	ServerID       string   `json:"server_id"`
	ServerName     string   `json:"server_name"`
	Scope          string   `json:"scope"`
	Created        string   `json:"created"`
	Roots          []string `json:"roots"`
	SourcePath     string   `json:"source_path"`
	OnlineSnapshot bool     `json:"online_snapshot"`
}

type BackupInfo struct {
	File      string `json:"file"`
	Path      string `json:"path"`
	Scope     string `json:"scope"`
	Created   string `json:"created"`
	Size      int64  `json:"size"`
	Verified  bool   `json:"verified"`
	SHA256    string `json:"sha256,omitempty"`
	Kind      string `json:"kind,omitempty"`
	Protected bool   `json:"protected,omitempty"`
	Trashed   bool   `json:"trashed,omitempty"`
	TrashedAt string `json:"trashed_at,omitempty"`
}

type backupTrashMetadata struct {
	OriginalKind string `json:"original_kind"`
	TrashedAt    string `json:"trashed_at"`
}

func backupBase(serverID string, checkpoints bool) string {
	root := "Backups"
	if checkpoints {
		root = "Checkpoints"
	}
	return filepath.Join(v4Root(), root, serverID)
}

func backupTrashBase(serverID string) string {
	return filepath.Join(v4Root(), "BackupTrash", serverID)
}

func backupProtectedMarker(path string) string {
	return path + ".protected"
}

func backupTrashMetadataPath(path string) string {
	return path + ".trash.json"
}

func backupKindForPath(serverID, path string) string {
	clean := filepath.Clean(path)
	if strings.EqualFold(filepath.Dir(clean), filepath.Clean(backupBase(serverID, true))) {
		return "checkpoint"
	}
	return "backup"
}

func backupIsProtected(path string) bool {
	st, err := os.Stat(backupProtectedMarker(path))
	return err == nil && !st.IsDir()
}

func setBackupProtected(path string, protected bool) error {
	marker := backupProtectedMarker(path)
	if protected {
		return os.WriteFile(marker, []byte("protected\r\n"), 0644)
	}
	if err := os.Remove(marker); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func readBackupSHA(path string) string {
	b, err := os.ReadFile(path + ".sha256")
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 {
		return ""
	}
	return fields[0]
}

func backupInfoFromPath(serverID, path, kind string, trashed bool) (BackupInfo, error) {
	m, err := readBackupManifest(path)
	if err != nil {
		return BackupInfo{}, err
	}
	st, err := os.Stat(path)
	if err != nil {
		return BackupInfo{}, err
	}
	info := BackupInfo{
		File:      filepath.Base(path),
		Path:      path,
		Scope:     m.Scope,
		Created:   m.Created,
		Size:      st.Size(),
		SHA256:    readBackupSHA(path),
		Kind:      kind,
		Protected: backupIsProtected(path),
		Trashed:   trashed,
	}
	info.Verified = info.SHA256 != ""
	if trashed {
		var meta backupTrashMetadata
		if b, e := os.ReadFile(backupTrashMetadataPath(path)); e == nil && json.Unmarshal(b, &meta) == nil {
			info.TrashedAt = meta.TrashedAt
			if strings.TrimSpace(meta.OriginalKind) != "" {
				info.Kind = meta.OriginalKind
			}
		}
	}
	return info, nil
}

func backupStorageBytes(items []BackupInfo) int64 {
	var total int64
	for _, item := range items {
		total += item.Size
	}
	return total
}

func backupRoots(dir, scope string) ([]string, error) {
	switch scope {
	case "world":
		roots := []string{}
		seen := map[string]bool{}
		level := readServerPropertyDefault(dir, "level-name", "world")
		for _, n := range []string{level, level + "_nether", level + "_the_end"} {
			if st, e := os.Stat(filepath.Join(dir, n)); e == nil && st.IsDir() {
				roots = append(roots, n)
				seen[strings.ToLower(n)] = true
			}
		}
		es, _ := os.ReadDir(dir)
		for _, e := range es {
			if !e.IsDir() {
				continue
			}
			if _, er := os.Stat(filepath.Join(dir, e.Name(), "level.dat")); er == nil && !seen[strings.ToLower(e.Name())] {
				roots = append(roots, e.Name())
			}
		}
		if len(roots) == 0 {
			return nil, fmt.Errorf("월드 폴더를 찾지 못했습니다")
		}
		return roots, nil
	case "config":
		candidates := []string{"server.properties", "bukkit.yml", "spigot.yml", "permissions.yml", "ops.json", "whitelist.json", "config", "plugins/GeumyiDiscordStatus", "plugins/GeumyiServerTools"}
		out := []string{}
		for _, x := range candidates {
			if _, e := os.Stat(filepath.Join(dir, filepath.FromSlash(x))); e == nil {
				out = append(out, x)
			}
		}
		if len(out) == 0 {
			return nil, fmt.Errorf("백업할 설정 파일이 없습니다")
		}
		return out, nil
	case "full":
		return []string{"."}, nil
	default:
		return nil, fmt.Errorf("unknown backup scope: %s", scope)
	}
}

func withOnlineWorldFreeze(s ServerConfig, fn func() error) error {
	online := tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond)
	if !online {
		return fn()
	}
	pass, e := readServerProperty(resolveServerDir(s), "rcon.password")
	if e != nil || strings.TrimSpace(pass) == "" {
		return fmt.Errorf("온라인 월드 백업은 RCON이 필요합니다")
	}
	if _, e = rconCommand("127.0.0.1", s.RCONPort, pass, "save-off"); e != nil {
		return fmt.Errorf("save-off 실패: %w", e)
	}
	defer func() { _, _ = rconCommand("127.0.0.1", s.RCONPort, pass, "save-on") }()
	if _, e = rconCommand("127.0.0.1", s.RCONPort, pass, "save-all flush"); e != nil {
		return fmt.Errorf("save-all flush 실패: %w", e)
	}
	return fn()
}

func addPathToZip(zw *zip.Writer, base, rel string) error {
	target := base
	if rel != "." {
		target = filepath.Join(base, filepath.FromSlash(rel))
	}
	return filepath.Walk(target, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return nil
		}
		r, e := filepath.Rel(base, path)
		if e != nil {
			return e
		}
		r = filepath.ToSlash(r)
		if r == "." {
			return nil
		}
		h, e := zip.FileInfoHeader(info)
		if e != nil {
			return e
		}
		h.Name = r
		if info.IsDir() {
			h.Name += "/"
			_, e = zw.CreateHeader(h)
			return e
		}
		h.Method = zip.Deflate
		w, e := zw.CreateHeader(h)
		if e != nil {
			return e
		}
		f, e := os.Open(path)
		if e != nil {
			return e
		}
		defer f.Close()
		_, e = io.Copy(w, f)
		return e
	})
}

func createBackup(s ServerConfig, scope string, checkpoints bool) (BackupInfo, error) {
	dir := resolveServerDir(s)
	if dir == "" {
		return BackupInfo{}, fmt.Errorf("server path missing")
	}
	roots, e := backupRoots(dir, scope)
	if e != nil {
		return BackupInfo{}, e
	}
	if scope == "full" && tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) {
		return BackupInfo{}, fmt.Errorf("전체 서버 백업은 서버를 정상 종료한 뒤 실행하세요")
	}
	root := backupBase(s.ID, checkpoints)
	if e = os.MkdirAll(root, 0755); e != nil {
		return BackupInfo{}, e
	}
	stamp := time.Now().Format("20060102-150405")
	kind := "backup"
	if checkpoints {
		kind = "checkpoint"
	}
	name := fmt.Sprintf("%s-%s-%s-%s.zip", s.ID, scope, kind, stamp)
	out := filepath.Join(root, name)
	tmp := out + ".tmp"
	manifest := BackupManifest{Format: 1, GSCVersion: appVersion, ServerID: s.ID, ServerName: s.Name, Scope: scope, Created: time.Now().Format(time.RFC3339), Roots: roots, SourcePath: dir, OnlineSnapshot: tcpOpen("127.0.0.1", s.JavaPort, 200*time.Millisecond)}
	do := func() error {
		f, e := os.Create(tmp)
		if e != nil {
			return e
		}
		zw := zip.NewWriter(f)
		mb, _ := json.MarshalIndent(manifest, "", "  ")
		mw, e := zw.Create("GSC_BACKUP_MANIFEST.json")
		if e == nil {
			_, e = mw.Write(mb)
		}
		if e == nil {
			for _, r := range roots {
				if e = addPathToZip(zw, dir, r); e != nil {
					break
				}
			}
		}
		ce := zw.Close()
		fe := f.Close()
		if e == nil {
			e = ce
		}
		if e == nil {
			e = fe
		}
		if e != nil {
			_ = os.Remove(tmp)
			return e
		}
		_ = os.Remove(out)
		return os.Rename(tmp, out)
	}
	if scope == "world" {
		e = withOnlineWorldFreeze(s, do)
	} else {
		e = do()
	}
	if e != nil {
		return BackupInfo{}, e
	}
	sha, e := fileSHA256(out)
	if e != nil {
		return BackupInfo{}, e
	}
	_ = os.WriteFile(out+".sha256", []byte(sha+"  "+filepath.Base(out)+"\r\n"), 0644)
	if checkpoints {
		if e = setBackupProtected(out, true); e != nil {
			return BackupInfo{}, fmt.Errorf("체크포인트 보호 표시 실패: %w", e)
		}
	}
	st, _ := os.Stat(out)
	kind := "backup"
	if checkpoints {
		kind = "checkpoint"
	}
	bi := BackupInfo{File: filepath.Base(out), Path: out, Scope: scope, Created: manifest.Created, Size: st.Size(), Verified: true, SHA256: sha, Kind: kind, Protected: checkpoints}
	appendV4Event("info", "backup", s.ID, "백업 완료: "+bi.File, fmt.Sprintf("scope=%s size=%d kind=%s", scope, bi.Size, kind))
	return bi, nil
}

func fileSHA256(p string) (string, error) {
	f, e := os.Open(p)
	if e != nil {
		return "", e
	}
	defer f.Close()
	h := sha256.New()
	if _, e = io.Copy(h, f); e != nil {
		return "", e
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func readBackupManifest(p string) (BackupManifest, error) {
	z, e := zip.OpenReader(p)
	if e != nil {
		return BackupManifest{}, e
	}
	defer z.Close()
	for _, f := range z.File {
		if f.Name == "GSC_BACKUP_MANIFEST.json" {
			rc, e := f.Open()
			if e != nil {
				return BackupManifest{}, e
			}
			defer rc.Close()
			var m BackupManifest
			e = json.NewDecoder(io.LimitReader(rc, 1<<20)).Decode(&m)
			return m, e
		}
	}
	return BackupManifest{}, fmt.Errorf("backup manifest missing")
}

func verifyBackup(p string) (BackupInfo, error) {
	m, e := readBackupManifest(p)
	if e != nil {
		return BackupInfo{}, e
	}
	z, e := zip.OpenReader(p)
	if e != nil {
		return BackupInfo{}, e
	}
	for _, f := range z.File {
		rc, e := f.Open()
		if e != nil {
			z.Close()
			return BackupInfo{}, e
		}
		_, e = io.Copy(io.Discard, rc)
		_ = rc.Close()
		if e != nil {
			z.Close()
			return BackupInfo{}, e
		}
	}
	_ = z.Close()
	sha, e := fileSHA256(p)
	if e != nil {
		return BackupInfo{}, e
	}
	if b, e2 := os.ReadFile(p + ".sha256"); e2 == nil {
		want := strings.Fields(string(b))
		if len(want) > 0 && !strings.EqualFold(want[0], sha) {
			return BackupInfo{}, fmt.Errorf("SHA-256 불일치")
		}
	}
	st, _ := os.Stat(p)
	return BackupInfo{File: filepath.Base(p), Path: p, Scope: m.Scope, Created: m.Created, Size: st.Size(), Verified: true, SHA256: sha}, nil
}

func listBackups(s ServerConfig) ([]BackupInfo, []BackupInfo) {
	active := []BackupInfo{}
	for _, item := range []struct {
		root string
		kind string
	}{
		{backupBase(s.ID, false), "backup"},
		{backupBase(s.ID, true), "checkpoint"},
	} {
		entries, _ := os.ReadDir(item.root)
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".zip") {
				continue
			}
			info, err := backupInfoFromPath(s.ID, filepath.Join(item.root, entry.Name()), item.kind, false)
			if err == nil {
				active = append(active, info)
			}
		}
	}
	trash := []BackupInfo{}
	trashRoot := backupTrashBase(s.ID)
	entries, _ := os.ReadDir(trashRoot)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".zip") {
			continue
		}
		info, err := backupInfoFromPath(s.ID, filepath.Join(trashRoot, entry.Name()), "backup", true)
		if err == nil {
			trash = append(trash, info)
		}
	}
	sort.Slice(active, func(i, j int) bool { return active[i].Created > active[j].Created })
	sort.Slice(trash, func(i, j int) bool {
		if trash[i].TrashedAt != trash[j].TrashedAt {
			return trash[i].TrashedAt > trash[j].TrashedAt
		}
		return trash[i].Created > trash[j].Created
	})
	return active, trash
}

func safeBackupPath(s ServerConfig, file string) (string, error) {
	base := backupBase(s.ID, false)
	cp := backupBase(s.ID, true)
	for _, root := range []string{base, cp} {
		p := filepath.Join(root, filepath.Base(file))
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			return p, nil
		}
	}
	return "", fmt.Errorf("backup not found")
}

func safeTrashedBackupPath(s ServerConfig, file string) (string, error) {
	p := filepath.Join(backupTrashBase(s.ID), filepath.Base(file))
	if st, err := os.Stat(p); err == nil && !st.IsDir() {
		return p, nil
	}
	return "", fmt.Errorf("trashed backup not found")
}

func moveBackupSidecars(from, to string) error {
	for _, suffix := range []string{".sha256", ".protected"} {
		src := from + suffix
		dst := to + suffix
		if _, err := os.Stat(src); err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return err
		}
		if err := os.Rename(src, dst); err != nil {
			return err
		}
	}
	return nil
}

func trashBackup(s ServerConfig, file string) (BackupInfo, error) {
	path, err := safeBackupPath(s, file)
	if err != nil {
		return BackupInfo{}, err
	}
	if backupIsProtected(path) {
		return BackupInfo{}, fmt.Errorf("보호된 백업은 보호 해제 후 삭제할 수 있습니다")
	}
	kind := backupKindForPath(s.ID, path)
	root := backupTrashBase(s.ID)
	if err = os.MkdirAll(root, 0755); err != nil {
		return BackupInfo{}, err
	}
	dst := filepath.Join(root, filepath.Base(path))
	if _, err = os.Stat(dst); err == nil {
		return BackupInfo{}, fmt.Errorf("휴지통에 같은 이름의 백업이 이미 있습니다")
	}
	if err = os.Rename(path, dst); err != nil {
		return BackupInfo{}, err
	}
	if err = moveBackupSidecars(path, dst); err != nil {
		_ = os.Rename(dst, path)
		_ = moveBackupSidecars(dst, path)
		return BackupInfo{}, err
	}
	meta := backupTrashMetadata{OriginalKind: kind, TrashedAt: time.Now().Format(time.RFC3339)}
	b, _ := json.MarshalIndent(meta, "", "  ")
	if err = os.WriteFile(backupTrashMetadataPath(dst), b, 0644); err != nil {
		_ = moveBackupSidecars(dst, path)
		_ = os.Rename(dst, path)
		return BackupInfo{}, err
	}
	info, err := backupInfoFromPath(s.ID, dst, kind, true)
	if err != nil {
		return BackupInfo{}, err
	}
	appendV4Event("warn", "backup", s.ID, "백업을 휴지통으로 이동: "+info.File, "kind="+kind)
	return info, nil
}

func restoreTrashedBackup(s ServerConfig, file string) (BackupInfo, error) {
	path, err := safeTrashedBackupPath(s, file)
	if err != nil {
		return BackupInfo{}, err
	}
	meta := backupTrashMetadata{OriginalKind: "backup"}
	if b, e := os.ReadFile(backupTrashMetadataPath(path)); e == nil {
		_ = json.Unmarshal(b, &meta)
	}
	checkpoint := strings.EqualFold(meta.OriginalKind, "checkpoint")
	dstRoot := backupBase(s.ID, checkpoint)
	if err = os.MkdirAll(dstRoot, 0755); err != nil {
		return BackupInfo{}, err
	}
	dst := filepath.Join(dstRoot, filepath.Base(path))
	if _, err = os.Stat(dst); err == nil {
		return BackupInfo{}, fmt.Errorf("복구 위치에 같은 이름의 백업이 이미 있습니다")
	}
	if err = os.Rename(path, dst); err != nil {
		return BackupInfo{}, err
	}
	if err = moveBackupSidecars(path, dst); err != nil {
		_ = os.Rename(dst, path)
		_ = moveBackupSidecars(dst, path)
		return BackupInfo{}, err
	}
	_ = os.Remove(backupTrashMetadataPath(path))
	info, err := backupInfoFromPath(s.ID, dst, meta.OriginalKind, false)
	if err != nil {
		return BackupInfo{}, err
	}
	appendV4Event("info", "backup", s.ID, "휴지통 백업 복구: "+info.File, "kind="+meta.OriginalKind)
	return info, nil
}

func permanentlyDeleteTrashedBackup(s ServerConfig, file string) error {
	path, err := safeTrashedBackupPath(s, file)
	if err != nil {
		return err
	}
	for _, p := range []string{path, path + ".sha256", backupProtectedMarker(path), backupTrashMetadataPath(path)} {
		if e := os.Remove(p); e != nil && !os.IsNotExist(e) {
			return e
		}
	}
	appendV4Event("warn", "backup", s.ID, "휴지통 백업 영구 삭제: "+filepath.Base(path), "")
	return nil
}

func apiV4BackupManage(w http.ResponseWriter, r *http.Request) {
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
	rel, err := beginV4Operation(s.ID, "backup-manage:"+q.Action)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	defer rel()

	switch q.Action {
	case "protect", "unprotect":
		path, err := safeBackupPath(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		protect := q.Action == "protect"
		if err = setBackupProtected(path, protect); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		info, err := backupInfoFromPath(s.ID, path, backupKindForPath(s.ID, path), false)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		appendV4Event("info", "backup", s.ID, map[bool]string{true: "백업 보호 설정", false: "백업 보호 해제"}[protect]+": "+info.File, "")
		writeJSON(w, map[string]any{"ok": true, "backup": info})
	case "trash":
		info, err := trashBackup(s, q.File)
		if err != nil {
			status := http.StatusInternalServerError
			if strings.Contains(err.Error(), "보호된") || strings.Contains(err.Error(), "같은 이름") {
				status = http.StatusConflict
			}
			http.Error(w, err.Error(), status)
			return
		}
		writeJSON(w, map[string]any{"ok": true, "backup": info})
	case "restore-trash":
		info, err := restoreTrashedBackup(s, q.File)
		if err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		writeJSON(w, map[string]any{"ok": true, "backup": info})
	case "delete-permanent":
		if err := permanentlyDeleteTrashedBackup(s, q.File); err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		writeJSON(w, map[string]any{"ok": true})
	default:
		http.Error(w, "action must be protect, unprotect, trash, restore-trash, or delete-permanent", http.StatusBadRequest)
	}
}

func apiV4Backup(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct{ ID, Scope string }
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	if q.Scope == "" {
		q.Scope = "world"
	}
	rel, e := beginV4Operation(s.ID, "backup:"+q.Scope)
	if e != nil {
		http.Error(w, e.Error(), 409)
		return
	}
	defer rel()
	bi, e := createBackup(s, q.Scope, false)
	if e != nil {
		appendV4Event("error", "backup", s.ID, "백업 실패", e.Error())
		http.Error(w, e.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "backup": bi})
}
func apiV4Backups(w http.ResponseWriter, r *http.Request) {
	s, ok := serverByID(r.URL.Query().Get("id"))
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	active, trash := listBackups(s)
	writeJSON(w, map[string]any{
		"backups": active,
		"trash": trash,
		"storage": map[string]any{
			"active_bytes": backupStorageBytes(active),
			"trash_bytes": backupStorageBytes(trash),
			"total_bytes": backupStorageBytes(active) + backupStorageBytes(trash),
		},
	})
}
func apiV4BackupVerify(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct{ ID, File string }
	_ = json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q)
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	p, e := safeBackupPath(s, q.File)
	if e != nil {
		http.Error(w, e.Error(), 404)
		return
	}
	bi, e := verifyBackup(p)
	if e != nil {
		appendV4Event("error", "backup", s.ID, "백업 검증 실패", e.Error())
		http.Error(w, e.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "backup": bi})
}

func extractBackup(p, dst string, m BackupManifest) error {
	z, e := zip.OpenReader(p)
	if e != nil {
		return e
	}
	defer z.Close()
	baseClean := filepath.Clean(dst) + string(os.PathSeparator)
	for _, f := range z.File {
		if f.Name == "GSC_BACKUP_MANIFEST.json" {
			continue
		}
		name := filepath.Clean(filepath.FromSlash(f.Name))
		target := filepath.Join(dst, name)
		tc := filepath.Clean(target)
		if tc != filepath.Clean(dst) && !strings.HasPrefix(tc, baseClean) {
			return fmt.Errorf("unsafe zip path: %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			if e = os.MkdirAll(target, 0755); e != nil {
				return e
			}
			continue
		}
		if e = os.MkdirAll(filepath.Dir(target), 0755); e != nil {
			return e
		}
		rc, e := f.Open()
		if e != nil {
			return e
		}
		tmp := target + ".gsc-restore"
		out, e := os.Create(tmp)
		if e != nil {
			rc.Close()
			return e
		}
		_, e = io.Copy(out, rc)
		ce := out.Close()
		_ = rc.Close()
		if e == nil {
			e = ce
		}
		if e != nil {
			_ = os.Remove(tmp)
			return e
		}
		_ = os.Remove(target)
		if e = os.Rename(tmp, target); e != nil {
			return e
		}
	}
	return nil
}

func restoreBackup(s ServerConfig, p string) (string, error) {
	if tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) || launchAlive(s.ID) {
		return "", fmt.Errorf("복원은 서버를 완전히 종료한 뒤 실행하세요")
	}
	m, e := readBackupManifest(p)
	if e != nil {
		return "", e
	}
	if m.ServerID != s.ID {
		return "", fmt.Errorf("다른 서버의 백업입니다: %s", m.ServerID)
	}
	if _, e = verifyBackup(p); e != nil {
		return "", fmt.Errorf("백업 검증 실패: %w", e)
	}
	cp, e := createBackup(s, m.Scope, true)
	if e != nil {
		return "", fmt.Errorf("복원 전 체크포인트 실패: %w", e)
	}
	dir := resolveServerDir(s)
	if m.Scope == "full" {
		old := dir + ".gsc-pre-restore-" + time.Now().Format("20060102-150405")
		if e = os.Rename(dir, old); e != nil {
			return cp.File, e
		}
		if e = os.MkdirAll(dir, 0755); e != nil {
			_ = os.Rename(old, dir)
			return cp.File, e
		}
		if e = extractBackup(p, dir, m); e != nil {
			_ = os.RemoveAll(dir)
			_ = os.Rename(old, dir)
			return cp.File, e
		}
		appendV4Event("warn", "restore", s.ID, "전체 서버 복원 완료", "이전 폴더: "+old)
		return cp.File, nil
	}
	if m.Scope == "world" {
		for _, root := range m.Roots {
			_ = os.RemoveAll(filepath.Join(dir, filepath.FromSlash(root)))
		}
	}
	if e = extractBackup(p, dir, m); e != nil {
		return cp.File, e
	}
	appendV4Event("warn", "restore", s.ID, "백업 복원 완료: "+filepath.Base(p), "checkpoint="+cp.File)
	return cp.File, nil
}

func apiV4Restore(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct{ ID, File string }
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	p, e := safeBackupPath(s, q.File)
	if e != nil {
		http.Error(w, e.Error(), 404)
		return
	}
	rel, e := beginV4Operation(s.ID, "restore")
	if e != nil {
		http.Error(w, e.Error(), 409)
		return
	}
	defer rel()
	cp, e := restoreBackup(s, p)
	if e != nil {
		appendV4Event("error", "restore", s.ID, "복원 실패", e.Error())
		http.Error(w, e.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "checkpoint": cp})
}
