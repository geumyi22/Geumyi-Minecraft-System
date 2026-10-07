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
	SourceReason   string   `json:"source_reason,omitempty"`
	OnlineSnapshot bool     `json:"online_snapshot"`
}

type BackupInfo struct {
	File         string `json:"file"`
	Path         string `json:"path"`
	Scope        string `json:"scope"`
	Created      string `json:"created"`
	Size         int64  `json:"size"`
	Verified     bool   `json:"verified"`
	SHA256       string `json:"sha256,omitempty"`
	Kind         string `json:"kind,omitempty"`
	Protected    bool   `json:"protected,omitempty"`
	Trashed      bool   `json:"trashed,omitempty"`
	SourceReason string `json:"source_reason,omitempty"`
}

func backupBase(serverID string, checkpoints bool) string {
	root := "Backups"
	if checkpoints {
		root = "Checkpoints"
	}
	return filepath.Join(v4Root(), root, serverID)
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

func estimateBackupSourceBytes(base string, roots []string) (int64, error) {
	var total int64
	seen := map[string]bool{}
	for _, rel := range roots {
		target := base
		if rel != "." {
			target = filepath.Join(base, filepath.FromSlash(rel))
		}
		err := filepath.Walk(target, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.Mode()&os.ModeSymlink != 0 {
				if info.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
			if info.IsDir() {
				return nil
			}
			clean := filepath.Clean(path)
			if seen[clean] {
				return nil
			}
			seen[clean] = true
			total += info.Size()
			return nil
		})
		if err != nil {
			return 0, err
		}
	}
	return total, nil
}

func backupDiskGuardForFree(sourceBytes, freeBytes int64) error {
	if sourceBytes < 0 {
		sourceBytes = 0
	}
	if freeBytes <= 0 {
		return nil
	}
	margin := sourceBytes / 10
	const minimumMargin = int64(512 << 20)
	if margin < minimumMargin {
		margin = minimumMargin
	}
	required := sourceBytes + margin
	if freeBytes < required {
		return fmt.Errorf("백업 디스크 여유 공간 부족: 예상 원본 %d bytes + 안전 여유 %d bytes, 사용 가능 %d bytes", sourceBytes, margin, freeBytes)
	}
	return nil
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

func normalizeBackupReason(reason string, checkpoints bool) string {
	reason = strings.TrimSpace(strings.NewReplacer("\r", " ", "\n", " ").Replace(reason))
	if reason == "" {
		if checkpoints {
			return "restore-checkpoint"
		}
		return "manual"
	}
	if len(reason) > 160 {
		reason = reason[:160]
	}
	return reason
}

func createBackup(s ServerConfig, scope string, checkpoints bool) (BackupInfo, error) {
	return createBackupWithReason(s, scope, checkpoints, "")
}

func createBackupWithReason(s ServerConfig, scope string, checkpoints bool, reason string) (BackupInfo, error) {
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
	sourceBytes, sizeErr := estimateBackupSourceBytes(dir, roots)
	if sizeErr != nil {
		return BackupInfo{}, fmt.Errorf("백업 크기 사전 계산 실패: %w", sizeErr)
	}
	freeBytes := int64(getHostStats().DiskFreeGB * 1073741824)
	if e = backupDiskGuardForFree(sourceBytes, freeBytes); e != nil {
		appendV4Event("warn", "backup", s.ID, "백업 디스크 가드 차단", e.Error())
		return BackupInfo{}, e
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
	reason = normalizeBackupReason(reason, checkpoints)
	manifest := BackupManifest{Format: 1, GSCVersion: appVersion, ServerID: s.ID, ServerName: s.Name, Scope: scope, Created: time.Now().Format(time.RFC3339), Roots: roots, SourcePath: dir, SourceReason: reason, OnlineSnapshot: tcpOpen("127.0.0.1", s.JavaPort, 200*time.Millisecond)}
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
	protected := false
	if checkpoints {
		meta := readBackupMeta(out)
		meta.Protected = true
		meta.ProtectedAt = time.Now().Format(time.RFC3339)
		if e = writeBackupMeta(out, meta); e != nil {
			return BackupInfo{}, fmt.Errorf("복원 체크포인트 보호 설정 실패: %w", e)
		}
		protected = true
	}
	st, _ := os.Stat(out)
	bi := BackupInfo{File: filepath.Base(out), Path: out, Scope: scope, Created: manifest.Created, Size: st.Size(), Verified: true, SHA256: sha, Kind: map[bool]string{true: "checkpoint", false: "backup"}[checkpoints], Protected: protected, SourceReason: manifest.SourceReason}
	appendV4Event("info", "backup", s.ID, "백업 완료: "+bi.File, fmt.Sprintf("scope=%s size=%d protected=%v reason=%s", scope, bi.Size, protected, manifest.SourceReason))
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
	return BackupInfo{File: filepath.Base(p), Path: p, Scope: m.Scope, Created: m.Created, Size: st.Size(), Verified: true, SHA256: sha, SourceReason: m.SourceReason}, nil
}

func listBackups(s ServerConfig) []BackupInfo {
	out := []BackupInfo{}
	for _, checkpoint := range []bool{false, true} {
		root := backupBase(s.ID, checkpoint)
		es, _ := os.ReadDir(root)
		for _, e := range es {
			if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".zip") {
				continue
			}
			p := filepath.Join(root, e.Name())
			m, er := readBackupManifest(p)
			if er != nil {
				continue
			}
			st, _ := e.Info()
			sha := ""
			if b, er := os.ReadFile(p + ".sha256"); er == nil {
				f := strings.Fields(string(b))
				if len(f) > 0 {
					sha = f[0]
				}
			}
			meta := readBackupMeta(p)
			out = append(out, BackupInfo{File: e.Name(), Path: p, Scope: m.Scope, Created: m.Created, Size: st.Size(), Verified: sha != "", SHA256: sha, Kind: map[bool]string{true: "checkpoint", false: "backup"}[checkpoint], Protected: meta.Protected, SourceReason: m.SourceReason})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created > out[j].Created })
	return out
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

func apiV4Backup(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		ID     string `json:"id"`
		Scope  string `json:"scope"`
		Reason string `json:"reason"`
	}
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
	bi, e := createBackupWithReason(s, q.Scope, false, q.Reason)
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
	writeJSON(w, map[string]any{"backups": listBackups(s)})
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

type RestorePreflight struct {
	ServerID          string   `json:"server_id"`
	File              string   `json:"file"`
	Scope             string   `json:"scope,omitempty"`
	SourceReason      string   `json:"source_reason,omitempty"`
	ServerOffline     bool     `json:"server_offline"`
	BackupVerified    bool     `json:"backup_verified"`
	ServerMatch       bool     `json:"server_match"`
	CheckpointReady   bool     `json:"checkpoint_ready"`
	PendingUpdate     bool     `json:"pending_update"`
	Ready             bool     `json:"ready"`
	Checks            []string `json:"checks"`
	BlockedReason     string   `json:"blocked_reason,omitempty"`
}

type RestoreHealth struct {
	OK     bool     `json:"ok"`
	Checks []string `json:"checks"`
}

func buildRestorePreflight(s ServerConfig, p string) RestorePreflight {
	out := RestorePreflight{ServerID: s.ID, File: filepath.Base(p), Checks: []string{}}
	out.PendingUpdate = hasPendingUpdate(s)
	if out.PendingUpdate {
		out.BlockedReason = "pending update transaction: restore is blocked until recovery/commit completes"
		out.Checks = append(out.Checks, "active update transaction blocks restore")
		return out
	}
	out.ServerOffline = !tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) && !launchAlive(s.ID)
	if !out.ServerOffline {
		out.BlockedReason = "복원은 서버를 완전히 종료한 뒤 실행하세요"
		out.Checks = append(out.Checks, "server must be fully offline")
		return out
	}
	out.Checks = append(out.Checks, "server offline")
	m, err := readBackupManifest(p)
	if err != nil {
		out.BlockedReason = "backup manifest: " + err.Error()
		return out
	}
	out.Scope = m.Scope
	out.SourceReason = m.SourceReason
	out.ServerMatch = m.ServerID == s.ID
	if !out.ServerMatch {
		out.BlockedReason = "다른 서버의 백업입니다: " + m.ServerID
		return out
	}
	out.Checks = append(out.Checks, "backup server id matched")
	if _, err = verifyBackup(p); err != nil {
		out.BlockedReason = "백업 검증 실패: " + err.Error()
		return out
	}
	out.BackupVerified = true
	out.Checks = append(out.Checks, "zip + SHA-256 verified")
	dir := resolveServerDir(s)
	roots, err := backupRoots(dir, m.Scope)
	if err != nil {
		out.BlockedReason = "복원 전 체크포인트 범위 확인 실패: " + err.Error()
		return out
	}
	sourceBytes, err := estimateBackupSourceBytes(dir, roots)
	if err != nil {
		out.BlockedReason = "복원 전 체크포인트 크기 계산 실패: " + err.Error()
		return out
	}
	freeBytes := int64(getHostStats().DiskFreeGB * 1073741824)
	if err = backupDiskGuardForFree(sourceBytes, freeBytes); err != nil {
		out.BlockedReason = "복원 전 체크포인트 디스크 가드: " + err.Error()
		return out
	}
	out.CheckpointReady = true
	out.Checks = append(out.Checks, "checkpoint disk guard passed")
	out.Ready = true
	return out
}

func restoreOfflineHealth(s ServerConfig, m BackupManifest) RestoreHealth {
	out := RestoreHealth{OK: true, Checks: []string{}}
	dir := resolveServerDir(s)
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		return RestoreHealth{OK: false, Checks: []string{"server directory missing after restore"}}
	}
	for _, root := range m.Roots {
		target := dir
		if root != "." {
			target = filepath.Join(dir, filepath.FromSlash(root))
		}
		if _, err := os.Stat(target); err != nil {
			out.OK = false
			out.Checks = append(out.Checks, "missing restored root: "+root)
		} else {
			out.Checks = append(out.Checks, "restored root present: "+root)
		}
	}
	if m.Scope == "full" {
		props := filepath.Join(dir, "server.properties")
		if _, err := os.Stat(props); err != nil {
			out.OK = false
			out.Checks = append(out.Checks, "server.properties missing")
		} else {
			out.Checks = append(out.Checks, "server.properties present")
		}
	}
	return out
}

func rollbackNonFullRestoreFromCheckpoint(s ServerConfig, checkpointFile string, target BackupManifest) error {
	cpPath, err := safeBackupPath(s, checkpointFile)
	if err != nil {
		return fmt.Errorf("checkpoint not found: %w", err)
	}
	cpManifest, err := readBackupManifest(cpPath)
	if err != nil {
		return fmt.Errorf("checkpoint manifest: %w", err)
	}
	if cpManifest.ServerID != s.ID || cpManifest.Scope != target.Scope {
		return fmt.Errorf("checkpoint scope/server mismatch")
	}
	if _, err = verifyBackup(cpPath); err != nil {
		return fmt.Errorf("checkpoint verification: %w", err)
	}
	dir := resolveServerDir(s)
	for _, root := range target.Roots {
		if root == "." {
			return fmt.Errorf("non-full rollback received full root")
		}
		if err = os.RemoveAll(filepath.Join(dir, filepath.FromSlash(root))); err != nil {
			return fmt.Errorf("rollback cleanup %s: %w", root, err)
		}
	}
	if err = extractBackup(cpPath, dir, cpManifest); err != nil {
		return fmt.Errorf("checkpoint extraction: %w", err)
	}
	health := restoreOfflineHealth(s, cpManifest)
	if !health.OK {
		return fmt.Errorf("checkpoint offline health: %s", strings.Join(health.Checks, "; "))
	}
	appendV4Event("warn", "restore", s.ID, "복원 실패 자동 rollback 완료",
		"checkpoint="+checkpointFile+" scope="+target.Scope)
	return nil
}

func restoreBackup(s ServerConfig, p string) (string, RestoreHealth, error) {
	pre := buildRestorePreflight(s, p)
	if !pre.Ready {
		return "", RestoreHealth{}, fmt.Errorf("%s", pre.BlockedReason)
	}
	m, e := readBackupManifest(p)
	if e != nil {
		return "", RestoreHealth{}, e
	}
	cp, e := createBackupWithReason(s, m.Scope, true, "restore-checkpoint:"+filepath.Base(p))
	if e != nil {
		return "", RestoreHealth{}, fmt.Errorf("복원 전 체크포인트 실패: %w", e)
	}
	dir := resolveServerDir(s)
	if m.Scope == "full" {
		old := dir + ".gsc-pre-restore-" + time.Now().Format("20060102-150405")
		if e = os.Rename(dir, old); e != nil {
			return cp.File, RestoreHealth{}, e
		}
		if e = os.MkdirAll(dir, 0755); e != nil {
			_ = os.Rename(old, dir)
			return cp.File, RestoreHealth{}, e
		}
		if e = extractBackup(p, dir, m); e != nil {
			_ = os.RemoveAll(dir)
			_ = os.Rename(old, dir)
			return cp.File, RestoreHealth{}, e
		}
		health := restoreOfflineHealth(s, m)
		if !health.OK {
			_ = os.RemoveAll(dir)
			_ = os.Rename(old, dir)
			return cp.File, health, fmt.Errorf("복원 후 offline health 실패: %s", strings.Join(health.Checks, "; "))
		}
		appendV4Event("warn", "restore", s.ID, "전체 서버 복원 완료", "이전 폴더: "+old+" checkpoint="+cp.File)
		return cp.File, health, nil
	}
	if m.Scope == "world" {
		for _, root := range m.Roots {
			if e = os.RemoveAll(filepath.Join(dir, filepath.FromSlash(root))); e != nil {
				if rb := rollbackNonFullRestoreFromCheckpoint(s, cp.File, m); rb != nil {
					return cp.File, RestoreHealth{}, fmt.Errorf("복원 대상 정리 실패: %v; checkpoint rollback 실패: %v", e, rb)
				}
				return cp.File, RestoreHealth{}, fmt.Errorf("복원 대상 정리 실패: %w; checkpoint rollback 완료", e)
			}
		}
	}
	if e = extractBackup(p, dir, m); e != nil {
		if rb := rollbackNonFullRestoreFromCheckpoint(s, cp.File, m); rb != nil {
			return cp.File, RestoreHealth{}, fmt.Errorf("백업 추출 실패: %v; checkpoint rollback 실패: %v", e, rb)
		}
		return cp.File, RestoreHealth{}, fmt.Errorf("백업 추출 실패: %w; checkpoint rollback 완료", e)
	}
	health := restoreOfflineHealth(s, m)
	if !health.OK {
		cause := fmt.Errorf("복원 후 offline health 실패: %s", strings.Join(health.Checks, "; "))
		if rb := rollbackNonFullRestoreFromCheckpoint(s, cp.File, m); rb != nil {
			return cp.File, health, fmt.Errorf("%v; checkpoint rollback 실패: %v", cause, rb)
		}
		return cp.File, health, fmt.Errorf("%v; checkpoint rollback 완료", cause)
	}
	appendV4Event("warn", "restore", s.ID, "백업 복원 완료: "+filepath.Base(p), "checkpoint="+cp.File+" offline_health=pass")
	return cp.File, health, nil
}

func apiV4RestorePreflight(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID   string `json:"id"`
		File string `json:"file"`
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
	p, err := safeBackupPath(s, q.File)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	writeJSON(w, buildRestorePreflight(s, p))
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
	cp, health, e := restoreBackup(s, p)
	if e != nil {
		appendV4Event("error", "restore", s.ID, "복원 실패", e.Error())
		http.Error(w, e.Error(), 500)
		return
	}
	appendAudit(r, "backup.restore", s.ID+":"+filepath.Base(p), "completed", "checkpoint="+cp+" offline_health=pass")
	writeJSON(w, map[string]any{"ok": true, "checkpoint": cp, "health": health})
}
