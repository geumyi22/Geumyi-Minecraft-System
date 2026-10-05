package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"regexp"
	"sort"
	"strings"
	"time"
)

type ExternalArtifact struct {
	Component      string            `json:"component"`
	Source         string            `json:"source"`
	Version        string            `json:"version"`
	Build          int               `json:"build,omitempty"`
	Channel        string            `json:"channel,omitempty"`
	Promoted       bool              `json:"promoted,omitempty"`
	File           string            `json:"file"`
	URL            string            `json:"url,omitempty"`
	SHA256         string            `json:"sha256,omitempty"`
	SHA256Verified bool              `json:"sha256_verified"`
	Installed      map[string]string `json:"installed,omitempty"`
	Status         string            `json:"status"`
	Message        string            `json:"message"`
	StageSupported bool              `json:"stage_supported"`
}

type geyserBuildResponse struct {
	Version   string `json:"version"`
	Build     int    `json:"build"`
	Channel   string `json:"channel"`
	Promoted  bool   `json:"promoted"`
	Downloads map[string]struct {
		Name   string `json:"name"`
		SHA256 string `json:"sha256"`
	} `json:"downloads"`
}

type githubExternalRelease struct {
	TagName string `json:"tag_name"`
	Draft   bool   `json:"draft"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
		Digest             string `json:"digest"`
		Size               int64  `json:"size"`
	} `json:"assets"`
}

var externalVersionRE = regexp.MustCompile(`(?i)^(ViaVersion|ViaBackwards)-(.+)\.jar$`)

func externalProxyRoot() string {
	return filepath.Join(v4Root(), "Network", "FourServer")
}

func externalHTTPClient() *http.Client {
	return &http.Client{Timeout: 20 * time.Second}
}

func parseSHA256Digest(v string) string {
	v = strings.TrimSpace(strings.ToLower(v))
	v = strings.TrimPrefix(v, "sha256:")
	if len(v) != 64 {
		return ""
	}
	for _, r := range v {
		if !((r >= '0' && r <= '9') || (r >= 'a' && r <= 'f')) {
			return ""
		}
	}
	return v
}

func externalInstalledProxyHashes(file string) map[string]string {
	out := map[string]string{}
	for _, id := range []string{"wild", "playground", "other"} {
		p := filepath.Join(externalProxyRoot(), id, "plugins", file)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			if sum, err := fileSHA256(p); err == nil {
				out[id] = strings.ToLower(sum)
			} else {
				out[id] = "hash-error"
			}
		} else {
			out[id] = "missing"
		}
	}
	return out
}

func externalInstalledViaVersions(prefix string) map[string]string {
	out := map[string]string{}
	for _, raw := range configSnapshot().Servers {
		s := normalizeServerConfig(raw)
		dir := resolveServerDir(s)
		if dir == "" {
			continue
		}
		plugins := filepath.Join(dir, "plugins")
		entries, _ := os.ReadDir(plugins)
		version := "missing"
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			m := externalVersionRE.FindStringSubmatch(e.Name())
			if len(m) == 3 && strings.EqualFold(m[1], prefix) {
				version = m[2]
				break
			}
		}
		out[s.ID] = version
	}
	return out
}

func externalCurrentAgainstSHA(installed map[string]string, target string) (string, string) {
	if target == "" {
		return "unknown", "공식 SHA-256 metadata가 없어 자동 staging을 차단합니다"
	}
	if len(installed) == 0 {
		return "missing", "설치 상태를 확인할 대상이 없습니다"
	}
	all := true
	missing := false
	for _, got := range installed {
		if got == "missing" {
			missing = true
			all = false
			continue
		}
		if !strings.EqualFold(got, target) {
			all = false
		}
	}
	if all {
		return "current", "모든 대상의 SHA-256이 최신 검증 artifact와 일치합니다"
	}
	if missing {
		return "update", "일부 대상에 artifact가 없거나 최신 artifact와 다릅니다"
	}
	return "update", "설치 artifact가 최신 검증 SHA-256과 다릅니다"
}

func fetchGeyserArtifact(project, expectedFile string) (ExternalArtifact, error) {
	client := externalHTTPClient()
	api := "https://download.geysermc.org/v2/projects/" + url.PathEscape(project) + "/versions/latest/builds/latest"
	req, _ := http.NewRequest(http.MethodGet, api, nil)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	resp, err := client.Do(req)
	if err != nil {
		return ExternalArtifact{}, fmt.Errorf("%s metadata 조회 실패: %w", project, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return ExternalArtifact{}, fmt.Errorf("%s metadata HTTP %d", project, resp.StatusCode)
	}
	var meta geyserBuildResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&meta); err != nil {
		return ExternalArtifact{}, fmt.Errorf("%s metadata 해석 실패: %w", project, err)
	}
	var key, sha string
	for k, d := range meta.Downloads {
		if d.Name == expectedFile {
			key = k
			sha = parseSHA256Digest(d.SHA256)
			break
		}
	}
	if key == "" || sha == "" || meta.Version == "" || meta.Build <= 0 {
		return ExternalArtifact{}, fmt.Errorf("%s 최신 build metadata에 검증 가능한 %s가 없습니다", project, expectedFile)
	}
	download := fmt.Sprintf("https://download.geysermc.org/v2/projects/%s/versions/%s/builds/%d/downloads/%s",
		url.PathEscape(project), url.PathEscape(meta.Version), meta.Build, url.PathEscape(key))
	return ExternalArtifact{
		Component: project, Source: "GeyserMC official metadata", Version: meta.Version,
		Build: meta.Build, Channel: meta.Channel, Promoted: meta.Promoted,
		File: expectedFile, URL: download, SHA256: sha, SHA256Verified: true, StageSupported: true,
	}, nil
}

func fetchGitHubExternalArtifact(owner, repo, prefix string) (ExternalArtifact, error) {
	client := externalHTTPClient()
	api := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", url.PathEscape(owner), url.PathEscape(repo))
	body, cached, err := githubPublicJSON(client, api, 4<<20)
	if err != nil {
		return ExternalArtifact{}, fmt.Errorf("%s release 조회 실패: %w", prefix, err)
	}
	var rel githubExternalRelease
	if err := json.Unmarshal(body, &rel); err != nil {
		return ExternalArtifact{}, fmt.Errorf("%s release 해석 실패: %w", prefix, err)
	}
	if rel.Draft || strings.TrimSpace(rel.TagName) == "" {
		return ExternalArtifact{}, fmt.Errorf("%s 최신 release가 배포 가능한 상태가 아닙니다", prefix)
	}
	for _, a := range rel.Assets {
		m := externalVersionRE.FindStringSubmatch(a.Name)
		if len(m) != 3 || !strings.EqualFold(m[1], prefix) {
			continue
		}
		sha := parseSHA256Digest(a.Digest)
		msg := map[bool]string{true: "GitHub asset SHA-256 digest 확인됨", false: "GitHub asset digest가 없어 자동 staging 차단"}[sha != ""]
		if cached {
			msg += " · GitHub API 캐시 사용"
		}
		return ExternalArtifact{
			Component: strings.ToLower(prefix), Source: "GitHub official release",
			Version: m[2], File: a.Name, URL: a.BrowserDownloadURL,
			SHA256: sha, SHA256Verified: sha != "", StageSupported: sha != "",
			Status: "unknown",
			Message: msg,
		}, nil
	}
	return ExternalArtifact{}, fmt.Errorf("%s release에서 JAR asset을 찾지 못했습니다", prefix)
}

func buildExternalStatus() ([]ExternalArtifact, []string) {
	items := []ExternalArtifact{}
	errs := []string{}

	for _, spec := range []struct{ project, file string }{
		{"geyser", "Geyser-Velocity.jar"},
		{"floodgate", "floodgate-velocity.jar"},
	} {
		a, err := fetchGeyserArtifact(spec.project, spec.file)
		if err != nil {
			errs = append(errs, err.Error())
			items = append(items, ExternalArtifact{Component: spec.project, Source: "GeyserMC official metadata", File: spec.file, Status: "error", Message: err.Error()})
			continue
		}
		a.Installed = externalInstalledProxyHashes(spec.file)
		a.Status, a.Message = externalCurrentAgainstSHA(a.Installed, a.SHA256)
		items = append(items, a)
	}

	for _, spec := range []struct{ repo, prefix string }{
		{"ViaVersion", "ViaVersion"},
		{"ViaBackwards", "ViaBackwards"},
	} {
		a, err := fetchGitHubExternalArtifact("ViaVersion", spec.repo, spec.prefix)
		if err != nil {
			errs = append(errs, err.Error())
			items = append(items, ExternalArtifact{Component: strings.ToLower(spec.prefix), Source: "GitHub official release", Status: "error", Message: err.Error()})
			continue
		}
		a.Installed = externalInstalledViaVersions(spec.prefix)
		allCurrent := len(a.Installed) > 0
		for _, v := range a.Installed {
			if v == "missing" || v != a.Version {
				allCurrent = false
			}
		}
		if allCurrent {
			a.Status = "current"
			a.Message = "모든 등록 backend에 최신 release가 설치되어 있습니다"
		} else {
			a.Status = "update"
			if a.SHA256Verified {
				a.Message = "업데이트 가능 · 공식 GitHub asset SHA-256 digest 검증 가능"
			} else {
				a.Message = "업데이트 감지 · 공식 SHA-256 digest가 없어 자동 staging은 차단"
			}
		}
		items = append(items, a)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Component < items[j].Component })
	return items, errs
}

func apiV4ExternalUpdateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	items, errs := buildExternalStatus()
	writeJSON(w, map[string]any{
		"schema": 1,
		"mode": "read-only",
		"live_files_modified": false,
		"proxy_root": externalProxyRoot(),
		"components": items,
		"errors": errs,
		"paper_policy": "notify/manual-approve",
	})
}

func safeExternalStageName(name string) (string, error) {
	base := filepath.Base(strings.TrimSpace(name))
	if base == "." || base == "" || !strings.HasSuffix(strings.ToLower(base), ".jar") {
		return "", errors.New("invalid external artifact file name")
	}
	return base, nil
}

func downloadExternalVerified(a ExternalArtifact, dst string) error {
	if !a.SHA256Verified || parseSHA256Digest(a.SHA256) == "" {
		return errors.New("verified SHA-256 is required")
	}
	u, err := url.Parse(a.URL)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return errors.New("HTTPS artifact URL required")
	}
	if u.Host != "download.geysermc.org" && u.Host != "github.com" {
		return fmt.Errorf("untrusted artifact host: %s", u.Host)
	}
	client := externalHTTPClient()
	req, _ := http.NewRequest(http.MethodGet, a.URL, nil)
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("download HTTP %d", resp.StatusCode)
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	tmp := dst + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	h := sha256.New()
	n, cpErr := io.Copy(io.MultiWriter(f, h), io.LimitReader(resp.Body, 96<<20))
	closeErr := f.Close()
	if cpErr != nil {
		_ = os.Remove(tmp)
		return cpErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	if n < 100000 || n >= 96<<20 {
		_ = os.Remove(tmp)
		return fmt.Errorf("suspicious artifact size: %d", n)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(got, a.SHA256) {
		_ = os.Remove(tmp)
		return fmt.Errorf("SHA-256 mismatch: expected %s got %s", a.SHA256, got)
	}
	_ = os.Remove(dst)
	if err := os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func apiV4ExternalUpdateStage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		Components []string `json:"components"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil && err != io.EOF {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	want := map[string]bool{}
	for _, v := range q.Components {
		want[strings.ToLower(strings.TrimSpace(v))] = true
	}
	all, metaErrs := buildExternalStatus()
	stamp := time.Now().Format("20060102-150405")
	root := filepath.Join(v4Root(), "Staging", "External", stamp)
	staged := []map[string]any{}
	blocked := []map[string]any{}
	skipped := []map[string]any{}
	for _, a := range all {
		if len(want) > 0 && !want[strings.ToLower(a.Component)] {
			continue
		}
		if a.Status == "current" {
			skipped = append(skipped, map[string]any{"component": a.Component, "reason": "already current"})
			continue
		}
		if !a.StageSupported || !a.SHA256Verified || a.URL == "" {
			blocked = append(blocked, map[string]any{"component": a.Component, "reason": a.Message})
			continue
		}
		name, err := safeExternalStageName(a.File)
		if err != nil {
			blocked = append(blocked, map[string]any{"component": a.Component, "reason": err.Error()})
			continue
		}
		dst := filepath.Join(root, name)
		if err := downloadExternalVerified(a, dst); err != nil {
			blocked = append(blocked, map[string]any{"component": a.Component, "reason": err.Error()})
			continue
		}
		staged = append(staged, map[string]any{
			"component": a.Component, "version": a.Version, "file": name,
			"sha256": a.SHA256, "path": dst, "live_applied": false,
		})
	}
	plan := map[string]any{
		"schema": 1, "created": time.Now().Format(time.RFC3339), "root": root,
		"staged": staged, "blocked": blocked, "skipped": skipped, "metadata_errors": metaErrs,
		"live_files_modified": false,
		"next_step": "maintenance approval + backup + player-aware restart + health gate + rollback",
	}
	if len(staged) > 0 {
		if err := os.MkdirAll(root, 0755); err == nil {
			if b, err := json.MarshalIndent(plan, "", "  "); err == nil {
				_ = os.WriteFile(filepath.Join(root, "external-stage-plan.json"), append(b, '\n'), 0644)
			}
		}
	}
	appendV4Event("info", "update", "", "외부 구성요소 staging 완료",
		fmt.Sprintf("staged=%d blocked=%d skipped=%d live_modified=false", len(staged), len(blocked), len(skipped)))
	writeJSON(w, plan)
}


type externalStagePlanFile struct {
	Schema  int    `json:"schema"`
	Root    string `json:"root"`
	Staged  []struct {
		Component string `json:"component"`
		Version   string `json:"version"`
		File      string `json:"file"`
		SHA256    string `json:"sha256"`
		Path      string `json:"path"`
	} `json:"staged"`
}

type externalProxyTarget struct {
	ID          string
	TaskName    string
	PublicJava  int
	PublicBedrock int
}

var day11ExternalProxyTargets = []externalProxyTarget{
	{ID: "wild", TaskName: "Geumyi Day10 Velocity wild", PublicJava: 25565, PublicBedrock: 19132},
	{ID: "playground", TaskName: "Geumyi Day10 Velocity playground", PublicJava: 25566, PublicBedrock: 19133},
	{ID: "other", TaskName: "Geumyi Day10 Velocity other", PublicJava: 25567, PublicBedrock: 19134},
}

func externalPathWithin(base, candidate string) bool {
	base = filepath.Clean(base)
	candidate = filepath.Clean(candidate)
	rel, err := filepath.Rel(base, candidate)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))
}

func latestExternalStageRoot() string {
	base := filepath.Join(v4Root(), "Staging", "External")
	entries, err := os.ReadDir(base)
	if err != nil {
		return ""
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(names)))
	for _, name := range names {
		root := filepath.Join(base, name)
		if _, err := os.Stat(filepath.Join(root, "external-stage-plan.json")); err == nil {
			return root
		}
	}
	return ""
}

func readExternalStagePlan(root string) (externalStagePlanFile, error) {
	var plan externalStagePlanFile
	base := filepath.Join(v4Root(), "Staging", "External")
	if strings.TrimSpace(root) == "" {
		root = latestExternalStageRoot()
	}
	root = filepath.Clean(root)
	if root == "." || root == "" || !externalPathWithin(base, root) {
		return plan, errors.New("invalid external stage root")
	}
	b, err := os.ReadFile(filepath.Join(root, "external-stage-plan.json"))
	if err != nil {
		return plan, err
	}
	if err := json.Unmarshal(b, &plan); err != nil {
		return plan, err
	}
	if plan.Schema != 1 {
		return plan, fmt.Errorf("unsupported external stage schema: %d", plan.Schema)
	}
	if filepath.Clean(plan.Root) != root {
		return plan, errors.New("external stage plan root mismatch")
	}
	for _, item := range plan.Staged {
		if item.Component != "geyser" && item.Component != "floodgate" {
			continue
		}
		name, err := safeExternalStageName(item.File)
		if err != nil {
			return plan, err
		}
		stagedPath := filepath.Join(root, name)
		if !externalPathWithin(root, stagedPath) {
			return plan, errors.New("unsafe staged artifact path")
		}
		got, err := fileSHA256(stagedPath)
		if err != nil {
			return plan, fmt.Errorf("%s staged hash read failed: %w", item.Component, err)
		}
		if !strings.EqualFold(got, item.SHA256) {
			return plan, fmt.Errorf("%s staged SHA-256 mismatch", item.Component)
		}
	}
	return plan, nil
}

func externalPlayersGate() error {
	for _, raw := range configSnapshot().Servers {
		s := normalizeServerConfig(raw)
		st := getServerStatus(s)
		if st.Online && st.MC.OK && st.MC.Online > 0 {
			return fmt.Errorf("%s에 플레이어 %d명 접속 중 · 외부 프록시 업데이트 차단", s.Name, st.MC.Online)
		}
	}
	return nil
}

func runScheduledTask(action, name string) error {
	if runtime.GOOS != "windows" {
		return errors.New("external proxy apply is Windows-only")
	}
	arg := "/Run"
	if action == "end" {
		arg = "/End"
	}
	out, err := exec.Command("schtasks.exe", arg, "/TN", name).CombinedOutput()
	if err != nil {
		return fmt.Errorf("scheduled task %s %s failed: %v · %s", action, name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func waitExternalProxyPorts(javaPort, bedrockPort int, want bool, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		javaOK := tcpOpen("127.0.0.1", javaPort, 250*time.Millisecond)
		bedrockOK := udpListening(bedrockPort)
		if javaOK == want && bedrockOK == want {
			return nil
		}
		time.Sleep(750 * time.Millisecond)
	}
	return fmt.Errorf("proxy port health timeout java=%d bedrock=%d want=%v", javaPort, bedrockPort, want)
}

func externalAtomicCopy(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".day11-new"
	_ = os.Remove(tmp)
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, cpErr := io.Copy(out, in)
	closeErr := out.Close()
	if cpErr != nil {
		_ = os.Remove(tmp)
		return cpErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	old := dst + ".day11-old"
	_ = os.Remove(old)
	if _, err := os.Stat(dst); err == nil {
		if err := os.Rename(dst, old); err != nil {
			_ = os.Remove(tmp)
			return err
		}
	}
	if err := os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		if _, statErr := os.Stat(old); statErr == nil {
			_ = os.Rename(old, dst)
		}
		return err
	}
	_ = os.Remove(old)
	return nil
}

func applyExternalProxyPlan(plan externalStagePlanFile) (map[string]any, error) {
	items := map[string]struct {
		File string
		SHA  string
	}{}
	for _, item := range plan.Staged {
		if item.Component == "geyser" || item.Component == "floodgate" {
			items[item.Component] = struct {
				File string
				SHA  string
			}{File: item.File, SHA: item.SHA256}
		}
	}
	if len(items) == 0 {
		return nil, errors.New("staged Geyser/Floodgate update가 없습니다")
	}
	if err := externalPlayersGate(); err != nil {
		return nil, err
	}

	backupRoot := filepath.Join(v4Root(), "Backups", "Day11-ExternalProxy-"+time.Now().Format("20060102-150405"))
	applied := []string{}
	for _, target := range day11ExternalProxyTargets {
		proxyDir := filepath.Join(externalProxyRoot(), target.ID)
		type backupRec struct {
			Live   string
			Backup string
			Exists bool
		}
		backups := []backupRec{}
		for _, item := range items {
			live := filepath.Join(proxyDir, "plugins", item.File)
			backup := filepath.Join(backupRoot, target.ID, "plugins", item.File)
			rec := backupRec{Live: live, Backup: backup}
			if _, err := os.Stat(live); err == nil {
				rec.Exists = true
				if err := externalAtomicCopy(live, backup); err != nil {
					return nil, fmt.Errorf("%s backup failed: %w", target.ID, err)
				}
			}
			backups = append(backups, rec)
		}

		if err := runScheduledTask("end", target.TaskName); err != nil {
			return nil, err
		}
		if err := waitExternalProxyPorts(target.PublicJava, target.PublicBedrock, false, 20*time.Second); err != nil {
			_ = runScheduledTask("run", target.TaskName)
			return nil, fmt.Errorf("%s proxy did not stop cleanly; live JAR unchanged: %w", target.ID, err)
		}

		replaceErr := error(nil)
		for _, item := range items {
			src := filepath.Join(plan.Root, item.File)
			dst := filepath.Join(proxyDir, "plugins", item.File)
			if err := externalAtomicCopy(src, dst); err != nil {
				replaceErr = err
				break
			}
			if got, err := fileSHA256(dst); err != nil || !strings.EqualFold(got, item.SHA) {
				if err != nil {
					replaceErr = err
				} else {
					replaceErr = fmt.Errorf("%s live SHA-256 mismatch", item.File)
				}
				break
			}
		}

		if replaceErr == nil {
			replaceErr = runScheduledTask("run", target.TaskName)
		}
		if replaceErr == nil {
			replaceErr = waitExternalProxyPorts(target.PublicJava, target.PublicBedrock, true, 90*time.Second)
		}

		if replaceErr != nil {
			_ = runScheduledTask("end", target.TaskName)
			_ = waitExternalProxyPorts(target.PublicJava, target.PublicBedrock, false, 10*time.Second)
			for _, rec := range backups {
				if rec.Exists {
					_ = externalAtomicCopy(rec.Backup, rec.Live)
				} else {
					_ = os.Remove(rec.Live)
				}
			}
			rollbackStartErr := runScheduledTask("run", target.TaskName)
			rollbackHealthErr := waitExternalProxyPorts(target.PublicJava, target.PublicBedrock, true, 90*time.Second)
			appendV4Event("error", "update", target.ID, "외부 프록시 업데이트 rollback",
				fmt.Sprintf("cause=%v restart=%v health=%v", replaceErr, rollbackStartErr, rollbackHealthErr))
			if rollbackStartErr != nil || rollbackHealthErr != nil {
				return nil, fmt.Errorf("%s apply failed (%v), rollback health failed (restart=%v health=%v)", target.ID, replaceErr, rollbackStartErr, rollbackHealthErr)
			}
			return nil, fmt.Errorf("%s apply failed and was rolled back safely: %w", target.ID, replaceErr)
		}
		applied = append(applied, target.ID)
		appendV4Event("info", "update", target.ID, "외부 프록시 구성요소 rolling 적용 완료",
			fmt.Sprintf("components=%d backup=%s", len(items), backupRoot))
	}

	return map[string]any{
		"ok": true,
		"mode": "rolling-proxy",
		"applied_proxies": applied,
		"components": len(items),
		"backup_root": backupRoot,
		"paper_touched": false,
		"floodgate_key_touched": false,
		"health_gate": "public Java TCP + Bedrock UDP",
	}, nil
}

func apiV4ExternalUpdateApplyProxy(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		Root    string `json:"root"`
		Confirm string `json:"confirm"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if q.Confirm != "APPLY_EXTERNAL_PROXY_UPDATE" {
		http.Error(w, "explicit confirmation required", http.StatusConflict)
		return
	}
	updateApplyMu.Lock()
	defer updateApplyMu.Unlock()

	plan, err := readExternalStagePlan(q.Root)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	result, err := applyExternalProxyPlan(plan)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, result)
}
