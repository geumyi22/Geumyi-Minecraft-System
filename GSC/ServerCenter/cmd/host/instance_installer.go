package main

// The personal creator only writes to a newly reserved directory. It never
// upgrades an existing server, starts a JVM server, or changes legacy profiles.
import (
	"archive/zip"
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const instanceMetadataLimit = 8 << 20
const instanceInstallerLimit = 128 << 20

var instanceVersionPattern = regexp.MustCompile(`^[0-9][0-9A-Za-z.+_-]{0,79}$`)
var instanceDownloadHosts = map[string]bool{
	"meta.fabricmc.net": true, "maven.fabricmc.net": true,
	"maven.minecraftforge.net": true, "maven.neoforged.net": true,
	"piston-meta.mojang.com": true, "launchermeta.mojang.com": true,
	"piston-data.mojang.com": true, "launcher.mojang.com": true,
	"fill.papermc.io": true, "fill-data.papermc.io": true,
	"api.purpurmc.org": true, "hub.spigotmc.org": true,
}

var instanceInstallHTTP = &http.Client{
	Timeout: 10 * time.Minute,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return errors.New("공식 다운로드 리디렉션이 너무 많습니다")
		}
		return validateInstanceDownloadURL(req.URL)
	},
}

func validateInstanceDownloadURL(u *url.URL) error {
	if u == nil || u.Scheme != "https" || u.User != nil || !instanceDownloadHosts[strings.ToLower(u.Hostname())] || (u.Port() != "" && u.Port() != "443") {
		return errors.New("허용된 공식 HTTPS 다운로드 주소가 아닙니다")
	}
	return nil
}

func instanceFetch(ctx context.Context, raw string, limit int64) ([]byte, error) {
	if limit <= instanceMetadataLimit {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, 45*time.Second)
		defer cancel()
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if err = validateInstanceDownloadURL(u); err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion+" (https://github.com/geumyi22/Geumyi-Minecraft-System)")
	resp, err := instanceInstallHTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("공식 서버 응답 %d (%s)", resp.StatusCode, u.Hostname())
	}
	if resp.ContentLength > limit {
		return nil, errors.New("다운로드 크기가 제한을 초과합니다")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, fmt.Errorf("다운로드가 중단됐습니다 (%d/%d bytes): %w", len(b), resp.ContentLength, err)
	}
	if int64(len(b)) > limit {
		return nil, errors.New("다운로드 크기가 제한을 초과합니다")
	}
	return b, nil
}

func instanceFetchJSON(ctx context.Context, raw string, value any) error {
	b, err := instanceFetch(ctx, raw, instanceMetadataLimit)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, value)
}

type instanceVersionList struct {
	Minecraft []string `json:"minecraft"`
	Loaders   []string `json:"loaders"`
	JavaMajor int      `json:"java_major,omitempty"`
}

type instanceMavenMetadata struct {
	Versions []string `xml:"versioning>versions>version"`
}
type instanceFabricVersion struct {
	Version string `json:"version"`
	Stable  bool   `json:"stable"`
	URL     string `json:"url"`
}

func instanceNeoMinecraft(v string) string {
	base := strings.Split(v, "-")[0]
	p := strings.Split(base, ".")
	if len(p) < 3 {
		return ""
	}
	major, err := strconv.Atoi(p[0])
	if err != nil {
		return ""
	}
	minor, err := strconv.Atoi(p[1])
	if err != nil {
		return ""
	}
	if major >= 26 {
		patch, err := strconv.Atoi(p[2])
		if err != nil {
			return ""
		}
		if patch == 0 {
			return fmt.Sprintf("%d.%d", major, minor)
		}
		return fmt.Sprintf("%d.%d.%d", major, minor, patch)
	}
	if major < 20 {
		return ""
	}
	if minor == 0 {
		return fmt.Sprintf("1.%d", major)
	}
	return fmt.Sprintf("1.%d.%d", major, minor)
}

func instanceVersionLess(a, b string) bool {
	parts := func(s string) []int {
		n := regexp.MustCompile(`[0-9]+`).FindAllString(s, -1)
		out := make([]int, len(n))
		for i, p := range n {
			out[i], _ = strconv.Atoi(p)
		}
		return out
	}
	aa, bb := parts(a), parts(b)
	for i := 0; i < len(aa) && i < len(bb); i++ {
		if aa[i] != bb[i] {
			return aa[i] > bb[i]
		}
	}
	if len(aa) != len(bb) {
		return len(aa) > len(bb)
	}
	// Stable builds sort ahead of their same-number prerelease.
	return a < b
}

func instanceOfficialVersions(ctx context.Context, kind, mc string) (instanceVersionList, error) {
	out := instanceVersionList{Minecraft: []string{}, Loaders: []string{}}
	if mc != "" && !instanceVersionPattern.MatchString(mc) {
		return out, errors.New("잘못된 Minecraft 버전입니다")
	}
	switch kind {
	case "vanilla", "paper", "purpur", "velocity":
		return instanceDirectVersions(ctx, kind, mc)
	case "spigot":
		return instanceSpigotVersions(ctx, mc)
	case "fabric":
		var games []instanceFabricVersion
		if err := instanceFetchJSON(ctx, "https://meta.fabricmc.net/v2/versions/game", &games); err != nil {
			return out, err
		}
		for _, g := range games {
			if g.Stable && instanceVersionPattern.MatchString(g.Version) {
				out.Minecraft = append(out.Minecraft, g.Version)
			}
		}
		if mc != "" {
			if !instanceContains(out.Minecraft, mc) {
				return out, errors.New("공식 Fabric 목록에 없는 Minecraft 버전입니다")
			}
			var loaders []struct {
				Loader instanceFabricVersion `json:"loader"`
			}
			if err := instanceFetchJSON(ctx, "https://meta.fabricmc.net/v2/versions/loader/"+mc, &loaders); err != nil {
				return out, err
			}
			for _, l := range loaders {
				if l.Loader.Stable && instanceVersionPattern.MatchString(l.Loader.Version) {
					out.Loaders = append(out.Loaders, l.Loader.Version)
				}
			}
		}
	case "forge", "neoforge":
		address := "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
		if kind == "neoforge" {
			address = "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"
		}
		b, err := instanceFetch(ctx, address, instanceMetadataLimit)
		if err != nil {
			return out, err
		}
		var meta instanceMavenMetadata
		if err := xml.Unmarshal(b, &meta); err != nil {
			return out, err
		}
		seen := map[string]bool{}
		for _, loader := range meta.Versions {
			if !instanceVersionPattern.MatchString(loader) {
				continue
			}
			game := instanceNeoMinecraft(loader)
			if kind == "forge" {
				game, _, _ = strings.Cut(loader, "-")
			}
			if game == "" || !instanceVersionPattern.MatchString(game) {
				continue
			}
			if !seen[game] {
				out.Minecraft = append(out.Minecraft, game)
				seen[game] = true
			}
			if game == mc {
				out.Loaders = append(out.Loaders, loader)
			}
		}
		sort.Slice(out.Minecraft, func(i, j int) bool { return instanceVersionLess(out.Minecraft[i], out.Minecraft[j]) })
		sort.Slice(out.Loaders, func(i, j int) bool { return instanceVersionLess(out.Loaders[i], out.Loaders[j]) })
	default:
		return out, errors.New("지원하지 않는 서버 종류입니다")
	}
	if mc != "" {
		if !instanceContains(out.Minecraft, mc) {
			return out, errors.New("공식 목록에 없는 Minecraft 버전입니다")
		}
		n, err := instanceRequiredJava(ctx, mc)
		if err != nil {
			return out, err
		}
		out.JavaMajor = n
	}
	return out, nil
}

func instanceContains(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func instanceRequiredJava(ctx context.Context, mc string) (int, error) {
	var manifest struct {
		Versions []struct {
			ID   string `json:"id"`
			URL  string `json:"url"`
			SHA1 string `json:"sha1"`
		} `json:"versions"`
	}
	if err := instanceFetchJSON(ctx, "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", &manifest); err != nil {
		return 0, err
	}
	for _, v := range manifest.Versions {
		if v.ID != mc {
			continue
		}
		b, err := instanceFetch(ctx, v.URL, instanceMetadataLimit)
		if err != nil {
			return 0, err
		}
		if len(v.SHA1) != 40 {
			return 0, errors.New("Minecraft 버전 메타데이터 해시가 없습니다")
		}
		sum := sha1.Sum(b)
		if !strings.EqualFold(hex.EncodeToString(sum[:]), v.SHA1) {
			return 0, errors.New("Minecraft 버전 메타데이터 해시 불일치")
		}
		var game struct {
			JavaVersion struct {
				Major int `json:"majorVersion"`
			} `json:"javaVersion"`
		}
		if err := json.Unmarshal(b, &game); err != nil {
			return 0, err
		}
		if game.JavaVersion.Major > 0 {
			return game.JavaVersion.Major, nil
		}
		// Historical manifests before JavaVersion was introduced used Java 8.
		if strings.HasPrefix(mc, "1.") {
			return 8, nil
		}
		return 0, errors.New("이 버전에 필요한 Java를 공식 정보에서 확인하지 못했습니다")
	}
	return 0, errors.New("Minecraft 공식 버전 정보를 찾지 못했습니다")
}

type instanceInstallRequest struct {
	ManagedInstance
	EULAAccepted   bool   `json:"eula_accepted"`
	BackendAddress string `json:"backend_address,omitempty"`
}
type instanceInstallJob struct {
	ID         string    `json:"id"`
	InstanceID string    `json:"instance_id"`
	Phase      string    `json:"phase"`
	Message    string    `json:"message"`
	Log        string    `json:"log"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	profile    ManagedInstance
}

var instanceInstallMu sync.Mutex
var instanceInstallJobs = map[string]*instanceInstallJob{}

// Call after claiming shuttingDown, before any shutdown side effects. Creation
// rechecks that flag under the same mutex before publishing a queued job, so a
// shutdown cannot miss a newly accepted installer process.
func instanceInstallShutdownError() error {
	instanceInstallMu.Lock()
	defer instanceInstallMu.Unlock()
	for _, job := range instanceInstallJobs {
		if job.Phase != "complete" && job.Phase != "failed" {
			return errors.New("서버 설치가 진행 중입니다. 설치가 끝난 뒤 전체 종료를 다시 실행하세요")
		}
	}
	return nil
}

func instanceInstallUpdate(id, phase, message string) {
	instanceInstallMu.Lock()
	defer instanceInstallMu.Unlock()
	if j := instanceInstallJobs[id]; j != nil {
		j.Phase = phase
		j.Message = message
		j.UpdatedAt = time.Now().UTC()
	}
}

type instanceInstallLog struct{ id string }

func (w instanceInstallLog) Write(p []byte) (int, error) {
	instanceInstallMu.Lock()
	defer instanceInstallMu.Unlock()
	if j := instanceInstallJobs[w.id]; j != nil {
		j.Log += string(p)
		if len(j.Log) > 65536 {
			j.Log = j.Log[len(j.Log)-65536:]
		}
		j.UpdatedAt = time.Now().UTC()
	}
	return len(p), nil
}

func registerInstanceInstallerRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v5/instances/versions", requireAuth(apiInstanceVersions))
	mux.HandleFunc("/api/v5/instances/create", withInstanceMutationAuth(apiInstanceCreate))
	mux.HandleFunc("/api/v5/instances/install-status", requireAuth(apiInstanceInstallStatus))
}

func apiInstanceVersions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	v, err := instanceOfficialVersions(ctx, r.URL.Query().Get("kind"), r.URL.Query().Get("minecraft"))
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	w.Header().Set("Cache-Control", "private, max-age=60")
	writeJSON(w, v)
}

func apiInstanceCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	if shuttingDown.Load() {
		http.Error(w, "Host 종료 중에는 생성할 수 없습니다", 409)
		return
	}
	var q instanceInstallRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 32<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&q); err != nil {
		http.Error(w, "요청 형식이 잘못되었습니다: "+err.Error(), 400)
		return
	}
	if !q.EULAAccepted {
		http.Error(w, "Minecraft EULA에 직접 동의해야 합니다", 400)
		return
	}
	if !instanceContains([]string{"vanilla", "paper", "spigot", "purpur", "fabric", "forge", "neoforge", "velocity"}, q.Kind) {
		http.Error(w, "지원하지 않는 서버 종류입니다", 400)
		return
	}
	if !instanceVersionPattern.MatchString(q.MinecraftVersion) || (q.LoaderVersion != "" && !instanceVersionPattern.MatchString(q.LoaderVersion)) {
		http.Error(w, "서버 버전을 선택하세요", 400)
		return
	}
	q.LaunchMode = "jar"
	q.LaunchFile = "server.jar"
	q.ManagementMode = "gsc"
	if q.Kind == "vanilla" {
		q.LoaderVersion = ""
	}
	q.TaskName = ""
	q.BridgePort = 0
	autoDir := strings.TrimSpace(q.Dir) == ""
	if err := applyInstanceCreationDefaults(&q.ManagedInstance); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	if q.Kind == "velocity" {
		var err error
		q.BackendAddress, err = validateInstanceBackend(q.BackendAddress)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err = validateInstanceProxyDestination(q.JavaPort, q.BackendAddress); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		q.LaunchFile = "velocity.jar"
	}
	p, err := validateManagedInstance(q.ManagedInstance)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	if _, err = os.Lstat(p.Dir); !os.IsNotExist(err) {
		http.Error(w, "기존 폴더는 덮어쓰지 않습니다. 아직 없는 새 폴더 경로를 지정하세요", 409)
		return
	}
	if autoDir {
		if err = os.MkdirAll(filepath.Dir(p.Dir), 0755); err != nil {
			http.Error(w, "서버 저장 폴더 생성 실패: "+err.Error(), 500)
			return
		}
	} else if st, statErr := os.Stat(filepath.Dir(p.Dir)); statErr != nil || !st.IsDir() {
		http.Error(w, "지정한 서버 폴더의 상위 폴더가 존재해야 합니다", 400)
		return
	}
	release, err := reserveInstanceDirectory(p.Dir)
	if err != nil {
		http.Error(w, err.Error(), 409)
		return
	}
	instanceInstallMu.Lock()
	if shuttingDown.Load() {
		instanceInstallMu.Unlock()
		release()
		http.Error(w, "Host 종료 중에는 생성할 수 없습니다", http.StatusConflict)
		return
	}
	active := 0
	for _, j := range instanceInstallJobs {
		if j.Phase == "complete" || j.Phase == "failed" {
			continue
		}
		active++
		if j.InstanceID == p.ID || j.profile.JavaPort == p.JavaPort {
			instanceInstallMu.Unlock()
			release()
			http.Error(w, "같은 ID 또는 포트의 서버를 이미 설치하고 있습니다", 409)
			return
		}
	}
	if active >= 2 {
		instanceInstallMu.Unlock()
		release()
		http.Error(w, "진행 중인 설치가 끝난 뒤 다시 시도하세요", 409)
		return
	}
	id := fmt.Sprintf("install-%d", time.Now().UnixNano())
	now := time.Now().UTC()
	instanceInstallJobs[id] = &instanceInstallJob{ID: id, InstanceID: p.ID, Phase: "queued", Message: "새 서버 설치 준비", CreatedAt: now, UpdatedAt: now, profile: p}
	instanceInstallMu.Unlock()
	go runInstanceInstall(id, p, release, q.BackendAddress)
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]any{"ok": true, "job_id": id})
}

func apiInstanceInstallStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	instanceInstallMu.Lock()
	j := instanceInstallJobs[r.URL.Query().Get("id")]
	if j == nil {
		instanceInstallMu.Unlock()
		http.Error(w, "설치 기록이 없습니다. Host가 재시작됐다면 생성 폴더를 확인하세요", 404)
		return
	}
	copy := *j
	instanceInstallMu.Unlock()
	writeJSON(w, copy)
}

func instanceJavaMajor(version string) int {
	p := strings.Split(version, ".")
	if len(p) > 1 && p[0] == "1" {
		p = p[1:]
	}
	if len(p) == 0 {
		return 0
	}
	n := regexp.MustCompile(`^[0-9]+`).FindString(p[0])
	major, _ := strconv.Atoi(n)
	return major
}

func runInstanceInstall(id string, p ManagedInstance, release func(), backend ...string) {
	// A failed installation is intentionally retained for inspection/recovery.
	defer release()
	if err := performInstanceInstall(id, &p, backend...); err != nil {
		instanceInstallUpdate(id, "failed", err.Error()+" · 기존 서버는 변경하지 않았습니다. 생성 폴더가 있다면 로그를 확인하세요.")
		return
	}
	instanceInstallUpdate(id, "registering", "설치 완료 · 서버 목록 등록 중")
	// Atomic catalog validation still rejects an intervening import/collision.
	release()
	if err := addManagedInstance(p); err != nil {
		instanceInstallUpdate(id, "failed", "파일 설치는 완료됐지만 등록 실패: "+err.Error()+" · 생성 폴더를 가져오기로 등록할 수 있습니다")
		return
	}
	instanceInstallUpdate(id, "complete", "서버 생성 완료 · 시작 버튼으로 실행하세요")
}

func performInstanceInstall(id string, p *ManagedInstance, backend ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Minute)
	defer cancel()
	instanceInstallUpdate(id, "validating", "공식 버전 및 Java 호환성 확인 중")
	versions, err := instanceOfficialVersions(ctx, p.Kind, p.MinecraftVersion)
	if err != nil {
		return err
	}
	if p.LoaderVersion == "" && len(versions.Loaders) > 0 {
		p.LoaderVersion = versions.Loaders[0]
	}
	if p.Kind != "vanilla" && !instanceContains(versions.Loaders, p.LoaderVersion) {
		return errors.New("선택한 버전에 해당하는 공식 로더 또는 빌드가 아닙니다")
	}
	j, err := resolveInstanceInstallJava(ctx, id, p, versions.JavaMajor)
	if err != nil {
		return err
	}
	p.JavaPath = j.Executable
	if err := os.Mkdir(p.Dir, 0755); err != nil {
		return fmt.Errorf("새 폴더 생성 실패: %w", err)
	}
	if err := writeInstanceNewFile(filepath.Join(p.Dir, ".gsc-install.json"), []byte(fmt.Sprintf("{\"instance_id\":%q,\"job_id\":%q,\"kind\":%q}\n", p.ID, id, p.Kind))); err != nil {
		return err
	}
	if instanceContains([]string{"vanilla", "paper", "purpur", "velocity"}, p.Kind) {
		artifact, err := instanceDirectArtifact(ctx, p.Kind, p.MinecraftVersion, p.LoaderVersion)
		if err != nil {
			return err
		}
		instanceInstallUpdate(id, "downloading", "공식 서버 다운로드 및 해시 검증 중")
		p.LaunchMode = "jar"
		p.LaunchFile = "server.jar"
		if p.Kind == "velocity" {
			p.LaunchFile = "velocity.jar"
		}
		if err = downloadInstanceServer(ctx, artifact, filepath.Join(p.Dir, p.LaunchFile), func(done, total int64) {
			instanceInstallUpdate(id, "downloading", fmt.Sprintf("공식 서버 다운로드 %.1f / %.1f MB", float64(done)/(1<<20), float64(total)/(1<<20)))
		}); err != nil {
			return err
		}
	} else if p.Kind == "spigot" {
		if err := installInstanceSpigot(ctx, id, p); err != nil {
			return err
		}
	} else {
		artifact, checksum, err := instanceInstallerArtifact(ctx, p.Kind, p.LoaderVersion)
		if err != nil {
			return err
		}
		instanceInstallUpdate(id, "downloading", "공식 설치 프로그램 다운로드 및 해시 검증 중")
		installer := filepath.Join(p.Dir, "gsc-loader-installer.jar")
		if err := downloadInstanceInstaller(ctx, artifact, checksum, installer); err != nil {
			return err
		}
		instanceInstallUpdate(id, "installing", "공식 설치 프로그램 실행 중 · 서버를 시작하지 않습니다")
		args := []string{"-jar", installer, "--installServer"}
		if p.Kind == "fabric" {
			args = []string{"-jar", installer, "server", "-mcversion", p.MinecraftVersion, "-loader", p.LoaderVersion, "-downloadMinecraft", "-dir", p.Dir}
		}
		args = append([]string{"-Dfile.encoding=UTF-8", "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-Dsun.stdout.encoding=UTF-8", "-Dsun.stderr.encoding=UTF-8"}, args...)
		cmd := exec.CommandContext(ctx, j.Executable, args...)
		cmd.Dir = p.Dir
		hideProcess(cmd)
		cmd.Stdout = instanceInstallLog{id}
		cmd.Stderr = instanceInstallLog{id}
		cmd.Env = instanceInstallerJavaEnv(j.Executable)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("공식 설치 프로그램 실패: %w (아래 설치 로그 확인)", err)
		}
		if err := instanceInstalledLaunch(p); err != nil {
			return err
		}
	}
	if p.Kind == "velocity" {
		address := ""
		if len(backend) > 0 {
			address = backend[0]
		}
		if err := writeInstanceVelocityConfig(p, address); err != nil {
			return err
		}
		_, _ = instanceInstallLog{id}.Write([]byte("새 프록시 설정 완료. 백엔드 서버 설정은 변경하지 않았습니다. 프록시를 통한 접속에는 별도 백엔드 설정 확인이 필요합니다.\n"))
		return nil
	}
	if err := writeInstanceNewFile(filepath.Join(p.Dir, "eula.txt"), []byte("# Accepted explicitly by the operator in GSC server creation.\neula=true\n")); err != nil {
		return err
	}
	properties := instanceNewServerProperties(p)
	if err := writeInstanceNewFile(filepath.Join(p.Dir, "server.properties"), []byte(properties)); err != nil {
		return err
	}
	if p.LaunchMode == "script" {
		argsFile := filepath.Join(p.Dir, "user_jvm_args.txt")
		original, err := os.ReadFile(argsFile)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		// Only the new official install directory is eligible for this edit.
		var lines []string
		for _, line := range strings.Split(string(original), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "-Xmx") || strings.HasPrefix(trimmed, "-Xms") {
				continue
			}
			lines = append(lines, line)
		}
		initialMB := 512
		if p.MemoryMB < initialMB {
			initialMB = p.MemoryMB
		}
		lines = append(lines, fmt.Sprintf("-Xms%dM\n-Xmx%dM", initialMB, p.MemoryMB))
		if err := os.WriteFile(argsFile, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
			return err
		}
	}
	_, _ = instanceInstallLog{id}.Write([]byte("\n설치 및 기본 설정 완료. 서버는 자동 시작하지 않았습니다.\n"))
	return nil
}

func instanceJavaRequirementSuffix(required int) string {
	if required >= 17 {
		return " 이상"
	}
	return ""
}

func instanceInstallerJavaEnv(java string) []string {
	javaBin := filepath.Dir(java)
	out := []string{}
	for _, e := range os.Environ() {
		k, _, _ := strings.Cut(e, "=")
		if strings.EqualFold(k, "JAVA_HOME") || strings.EqualFold(k, "PATH") {
			continue
		}
		out = append(out, e)
	}
	return append(out, "JAVA_HOME="+filepath.Dir(javaBin), "PATH="+javaBin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func instanceInstallerArtifact(ctx context.Context, kind, loader string) (string, string, error) {
	if !instanceVersionPattern.MatchString(loader) {
		return "", "", errors.New("잘못된 로더 버전")
	}
	switch kind {
	case "fabric":
		var installers []instanceFabricVersion
		if err := instanceFetchJSON(ctx, "https://meta.fabricmc.net/v2/versions/installer", &installers); err != nil {
			return "", "", err
		}
		for _, i := range installers {
			if i.Stable && instanceVersionPattern.MatchString(i.Version) {
				u := "https://maven.fabricmc.net/net/fabricmc/fabric-installer/" + i.Version + "/fabric-installer-" + i.Version + ".jar"
				return u, u + ".sha256", nil
			}
		}
	case "forge":
		u := "https://maven.minecraftforge.net/net/minecraftforge/forge/" + loader + "/forge-" + loader + "-installer.jar"
		return u, u + ".sha1", nil
	case "neoforge":
		u := "https://maven.neoforged.net/releases/net/neoforged/neoforge/" + loader + "/neoforge-" + loader + "-installer.jar"
		return u, u + ".sha256", nil
	}
	return "", "", errors.New("공식 설치 프로그램을 찾지 못했습니다")
}

func downloadInstanceInstaller(ctx context.Context, artifact, checksum, destination string) error {
	hashText, err := instanceFetch(ctx, checksum, 1024)
	if err != nil {
		return fmt.Errorf("설치 프로그램 해시 조회 실패: %w", err)
	}
	fields := strings.Fields(string(hashText))
	if len(fields) == 0 {
		return errors.New("설치 프로그램 해시가 비어 있습니다")
	}
	want := strings.ToLower(fields[0])
	length := 64
	if strings.HasSuffix(checksum, ".sha1") {
		length = 40
	}
	if len(want) != length {
		return errors.New("설치 프로그램 해시 형식이 잘못되었습니다")
	}
	if _, err := hex.DecodeString(want); err != nil {
		return err
	}
	b, err := instanceFetch(ctx, artifact, instanceInstallerLimit)
	if err != nil {
		return err
	}
	got := ""
	if length == 40 {
		s := sha1.Sum(b)
		got = hex.EncodeToString(s[:])
	} else {
		s := sha256.Sum256(b)
		got = hex.EncodeToString(s[:])
	}
	if got != want {
		return errors.New("공식 설치 프로그램 해시가 일치하지 않습니다")
	}
	if err := writeInstanceNewFile(destination, b); err != nil {
		return err
	}
	z, err := zip.OpenReader(destination)
	if err != nil {
		return errors.New("다운로드한 설치 프로그램이 올바른 JAR가 아닙니다")
	}
	defer z.Close()
	for _, f := range z.File {
		if f.Name == "META-INF/MANIFEST.MF" {
			return nil
		}
	}
	return errors.New("설치 프로그램 JAR manifest가 없습니다")
}

func writeInstanceNewFile(path string, b []byte) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, err = f.Write(b)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func instanceInstalledLaunch(p *ManagedInstance) error {
	if p.Kind == "fabric" {
		for _, name := range []string{"fabric-server-launch.jar", "fabric-server-launcher.jar"} {
			if st, err := os.Stat(filepath.Join(p.Dir, name)); err == nil && !st.IsDir() {
				p.LaunchMode = "jar"
				p.LaunchFile = name
				return nil
			}
		}
		return errors.New("Fabric 설치 결과에 서버 런처 JAR가 없습니다")
	}
	script := "run.bat"
	if runtime.GOOS != "windows" {
		script = "run.sh"
	}
	if st, err := os.Stat(filepath.Join(p.Dir, script)); err == nil && !st.IsDir() {
		p.LaunchMode = "script"
		p.LaunchFile = script
		return nil
	}
	// Forge before 1.17 starts with the installed universal server JAR.
	if p.Kind == "forge" {
		for _, name := range []string{"forge-" + p.LoaderVersion + ".jar", "forge-" + p.LoaderVersion + "-universal.jar"} {
			if st, err := os.Stat(filepath.Join(p.Dir, name)); err == nil && !st.IsDir() {
				p.LaunchMode = "jar"
				p.LaunchFile = name
				return nil
			}
		}
	}
	return errors.New("설치 프로그램이 서버 실행 파일을 만들지 못했습니다. 설치 로그를 확인하세요")
}
