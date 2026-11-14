package main

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// Official Jenkins build 201, retrieved and SHA-256 pinned on 2026-11-15.
// A moving latest URL is intentionally not used for executable code.
const instanceBuildToolsNumber = 201
const instanceBuildToolsURL = "https://hub.spigotmc.org/jenkins/job/BuildTools/201/artifact/target/BuildTools.jar"
const instanceBuildToolsSHA256 = "81ed06f5ce5fb705b558bf9b3cc2c5c53cdd9742406c5338c452faa13a1e1c24"

var instanceSpigotReleaseRE = regexp.MustCompile(`^[0-9]+(?:\.[0-9]+){1,2}$`)
var instanceSpigotIndexRE = regexp.MustCompile(`href="([0-9]+(?:\.[0-9]+){1,2})\.json"`)

type instanceSpigotManifest struct {
	Name         string            `json:"name"`
	Refs         map[string]string `json:"refs"`
	ToolsVersion int               `json:"toolsVersion"`
	JavaVersions []int             `json:"javaVersions"`
}

func instanceReadSpigotManifest(ctx context.Context, mc string) (instanceSpigotManifest, error) {
	var m instanceSpigotManifest
	if !instanceSpigotReleaseRE.MatchString(mc) {
		return m, errors.New("Spigot 정식 Minecraft 버전을 선택하세요")
	}
	if err := instanceFetchJSON(ctx, "https://hub.spigotmc.org/versions/"+mc+".json", &m); err != nil {
		return m, err
	}
	if !regexp.MustCompile(`^[0-9]+$`).MatchString(m.Name) || len(m.Refs["Spigot"]) != 40 || m.ToolsVersion > instanceBuildToolsNumber {
		return m, errors.New("Spigot 버전 정보가 올바르지 않거나 더 새로운 BuildTools가 필요합니다")
	}
	for _, ref := range m.Refs {
		if _, err := hex.DecodeString(ref); err != nil || len(ref) != 40 {
			return m, errors.New("Spigot 소스 버전 정보가 올바르지 않습니다")
		}
	}
	if len(m.JavaVersions) != 0 && (len(m.JavaVersions) != 2 || m.JavaVersions[0] < 52 || m.JavaVersions[1] < m.JavaVersions[0]) {
		return m, errors.New("Spigot Java 호환 범위를 읽을 수 없습니다")
	}
	return m, nil
}

func instanceSpigotVersions(ctx context.Context, mc string) (instanceVersionList, error) {
	out := instanceVersionList{Minecraft: []string{}, Loaders: []string{}}
	b, err := instanceFetch(ctx, "https://hub.spigotmc.org/versions/", instanceMetadataLimit)
	if err != nil {
		return out, err
	}
	seen := map[string]bool{}
	for _, m := range instanceSpigotIndexRE.FindAllStringSubmatch(string(b), -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			out.Minecraft = append(out.Minecraft, m[1])
		}
	}
	if len(out.Minecraft) == 0 {
		return out, errors.New("Spigot 공식 버전 목록이 비어 있습니다")
	}
	sort.Slice(out.Minecraft, func(i, j int) bool { return instanceVersionLess(out.Minecraft[i], out.Minecraft[j]) })
	if mc != "" {
		if !seen[mc] {
			return out, errors.New("Spigot 공식 목록에 없는 버전입니다")
		}
		m, err := instanceReadSpigotManifest(ctx, mc)
		if err != nil {
			return out, err
		}
		out.Loaders = []string{m.Name}
		if len(m.JavaVersions) == 2 {
			out.JavaMajor = m.JavaVersions[0] - 44
		} else {
			out.JavaMajor, err = instanceRequiredJava(ctx, mc)
			if err != nil {
				return out, err
			}
		}
	}
	return out, nil
}

func instanceSpigotFreshDirectory(id string, p ManagedInstance) error {
	entries, err := os.ReadDir(p.Dir)
	if err != nil {
		return err
	}
	if len(entries) != 1 || entries[0].Name() != ".gsc-install.json" || entries[0].IsDir() {
		return errors.New("Spigot 설치는 이번 작업에서 만든 새 폴더에서만 가능합니다")
	}
	if st, err := os.Lstat(p.Dir); err != nil || st.Mode()&os.ModeSymlink != 0 {
		return errors.New("Spigot 설치 폴더를 확인하지 못했습니다")
	}
	b, err := os.ReadFile(filepath.Join(p.Dir, ".gsc-install.json"))
	if err != nil {
		return err
	}
	var marker struct {
		InstanceID string `json:"instance_id"`
		JobID      string `json:"job_id"`
		Kind       string `json:"kind"`
	}
	if json.Unmarshal(b, &marker) != nil || marker.InstanceID != p.ID || marker.JobID != id || marker.Kind != "spigot" {
		return errors.New("현재 Spigot 설치 작업의 새 폴더 표시가 아닙니다")
	}
	return nil
}

func installInstanceSpigot(ctx context.Context, id string, p *ManagedInstance) error {
	if p.Kind != "spigot" {
		return errors.New("Spigot 전용 설치 경로입니다")
	}
	if err := instanceSpigotFreshDirectory(id, *p); err != nil {
		return err
	}
	manifest, err := instanceReadSpigotManifest(ctx, p.MinecraftVersion)
	if err != nil {
		return err
	}
	if p.LoaderVersion != manifest.Name {
		return errors.New("Spigot 빌드 정보가 변경됐습니다. 공식 버전을 새로 조회하여 다시 설치하세요")
	}
	j, err := javaruntime.Resolve(p.JavaPath)
	if err != nil {
		return err
	}
	compiler := "javac"
	if runtime.GOOS == "windows" {
		compiler += ".exe"
	}
	if st, err := os.Stat(filepath.Join(j.Home, "bin", compiler)); err != nil || st.IsDir() {
		return errors.New("Spigot 빌드에는 JRE가 아닌 JDK가 필요합니다. Java 자동 선택 또는 JDK 경로를 사용하세요")
	}
	major := instanceJavaMajor(j.Version)
	if len(manifest.JavaVersions) == 2 && (major < manifest.JavaVersions[0]-44 || major > manifest.JavaVersions[1]-44) {
		return fmt.Errorf("이 Spigot 버전의 공식 Java 범위는 %d~%d입니다 (선택: %d)", manifest.JavaVersions[0]-44, manifest.JavaVersions[1]-44, major)
	}
	gitDirs, err := instanceSpigotGit(ctx, id)
	if err != nil {
		return err
	}
	buildDir := filepath.Join(p.Dir, ".gsc-buildtools")
	if err = os.Mkdir(buildDir, 0700); err != nil {
		return err
	}
	instanceInstallUpdate(id, "downloading", "공식 Spigot BuildTools 다운로드 및 SHA-256 검증 중")
	b, err := instanceFetch(ctx, instanceBuildToolsURL, instanceInstallerLimit)
	if err != nil {
		return err
	}
	hash := sha256.Sum256(b)
	if hex.EncodeToString(hash[:]) != instanceBuildToolsSHA256 {
		return errors.New("공식 BuildTools 201의 SHA-256이 일치하지 않습니다")
	}
	installer := filepath.Join(buildDir, "BuildTools.jar")
	if err = writeInstanceNewFile(installer, b); err != nil {
		return err
	}
	cacheHome := filepath.Join(buildDir, "cache", "java-home")
	cacheMaven := filepath.Join(buildDir, "cache", "m2")
	for _, dir := range []string{cacheHome, cacheMaven, filepath.Join(buildDir, "output")} {
		if err = os.MkdirAll(dir, 0700); err != nil {
			return err
		}
	}
	gitConfig := filepath.Join(buildDir, "cache", "gitconfig")
	if err = writeInstanceNewFile(gitConfig, []byte("[core]\n\tlongpaths = true\n[user]\n\tname = GSC BuildTools\n\temail = buildtools@localhost\n")); err != nil {
		return err
	}
	log, err := os.OpenFile(filepath.Join(buildDir, "gsc-build.log"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer log.Close()
	args := []string{"-Duser.home=" + filepath.ToSlash(cacheHome), "-jar", installer, "--rev", p.MinecraftVersion, "--compile", "SPIGOT", "--nogui", "--output-dir", "output", "--final-name", "server.jar"}
	cmd := exec.CommandContext(ctx, j.Executable, args...)
	cmd.Dir = buildDir
	hideProcess(cmd)
	// A timed-out build owns its Maven/Git children. End that new build tree only,
	// so an installer timeout cannot leave a compiler running after its job fails.
	if runtime.GOOS == "windows" {
		cmd.Cancel = func() error {
			if cmd.Process == nil {
				return nil
			}
			return killProcessTree(cmd.Process.Pid)
		}
	}
	cmd.Env = instanceSpigotBuildEnv(j.Executable, gitDirs, cacheHome, cacheMaven, gitConfig)
	cmd.Stdout = io.MultiWriter(log, instanceInstallLog{id})
	cmd.Stderr = cmd.Stdout
	instanceInstallUpdate(id, "installing", "공식 BuildTools로 Spigot 빌드 중 · 첫 빌드는 시간이 걸릴 수 있습니다")
	if err = cmd.Run(); err != nil {
		return fmt.Errorf("Spigot BuildTools 빌드 실패: %w (생성 폴더의 .gsc-buildtools/gsc-build.log 확인)", err)
	}
	// Check the actual local checkouts, avoiding a second metadata network dependency
	// after a successful build and detecting a moving --rev manifest during startup.
	if err := instanceSpigotVerifyRefs(ctx, buildDir, gitDirs, cmd.Env, manifest); err != nil {
		return err
	}
	result := filepath.Join(buildDir, "output", "server.jar")
	if err = instanceSpigotCheckJar(result); err != nil {
		return err
	}
	src, err := os.Open(result)
	if err != nil {
		return err
	}
	defer src.Close()
	dst, err := os.OpenFile(filepath.Join(p.Dir, "server.jar"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(dst, src)
	closeErr := dst.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}
	sum, err := fileSHA256(filepath.Join(p.Dir, "server.jar"))
	if err != nil {
		return err
	}
	_, _ = instanceInstallLog{id}.Write([]byte("\nSpigot server.jar 생성 및 JAR 검사 완료. SHA-256: " + sum + "\n"))
	p.LaunchMode = "jar"
	p.LaunchFile = "server.jar"
	return nil
}

func instanceSpigotVerifyRefs(ctx context.Context, buildDir string, gitDirs, env []string, m instanceSpigotManifest) error {
	if len(gitDirs) == 0 {
		return errors.New("빌드 검증에 사용할 Git 경로가 없습니다")
	}
	name := "git"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	git := filepath.Join(gitDirs[0], name)
	for _, repo := range []string{"BuildData", "Bukkit", "CraftBukkit", "Spigot"} {
		want := m.Refs[repo]
		if len(want) != 40 {
			return errors.New("Spigot 공식 소스 버전 정보가 불완전합니다")
		}
		cmd := exec.CommandContext(ctx, git, "-C", filepath.Join(buildDir, repo), "rev-parse", "HEAD")
		cmd.Env = env
		hideProcess(cmd)
		out, err := cmd.Output()
		if err != nil || !strings.EqualFold(strings.TrimSpace(string(out)), want) {
			return fmt.Errorf("%s 소스 버전이 선택한 Spigot 빌드와 일치하지 않습니다. 빌드 결과는 보존했으며 등록하지 않았습니다", repo)
		}
	}
	return nil
}

func instanceSpigotCheckJar(path string) error {
	st, err := os.Stat(path)
	if err != nil || st.IsDir() || st.Size() < 1024 || st.Size() > 512<<20 {
		return errors.New("BuildTools가 올바른 크기의 Spigot 서버 JAR를 만들지 못했습니다")
	}
	z, err := zip.OpenReader(path)
	if err != nil {
		return errors.New("Spigot 빌드 결과가 올바른 JAR가 아닙니다")
	}
	defer z.Close()
	for _, f := range z.File {
		if f.Name == "META-INF/MANIFEST.MF" {
			r, e := f.Open()
			if e != nil {
				return e
			}
			b, e := io.ReadAll(io.LimitReader(r, 65537))
			r.Close()
			if e == nil && len(b) <= 65536 && strings.Contains(string(b), "Main-Class:") {
				return nil
			}
		}
	}
	return errors.New("Spigot 빌드 JAR에 실행 진입점이 없습니다")
}

func instanceSpigotBuildEnv(java string, gitDirs []string, cacheHome, cacheMaven, gitConfig string) []string {
	env := instanceInstallerJavaEnv(java)
	out := []string{}
	for _, e := range env {
		k, _, _ := strings.Cut(e, "=")
		upper := strings.ToUpper(k)
		if strings.HasPrefix(upper, "GIT_") || strings.HasPrefix(upper, "MAVEN_") || strings.HasPrefix(upper, "M2_") {
			continue
		}
		switch upper {
		case "PATH", "MAVEN_OPTS", "M2_HOME", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS":
			continue
		}
		out = append(out, e)
	}
	path := append([]string{filepath.Dir(java)}, gitDirs...)
	path = append(path, os.Getenv("PATH"))
	return append(out, "PATH="+strings.Join(path, string(os.PathListSeparator)), "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL="+gitConfig,
		`MAVEN_OPTS=-Xmx1024M -Dmaven.repo.local="`+filepath.ToSlash(cacheMaven)+`" -Duser.home="`+filepath.ToSlash(cacheHome)+`"`)
}

var instancePortableGitMu sync.Mutex
var instancePortableGitAssetRE = regexp.MustCompile(`^PortableGit-[0-9][0-9.]*-64-bit\.7z\.exe$`)

type instanceGitRelease struct {
	Tag        string `json:"tag_name"`
	Draft      bool   `json:"draft"`
	Prerelease bool   `json:"prerelease"`
	Assets     []struct {
		Name   string `json:"name"`
		URL    string `json:"browser_download_url"`
		Digest string `json:"digest"`
		Size   int64  `json:"size"`
	} `json:"assets"`
}

func instanceGitURLAllowed(u *url.URL, redirect bool) bool {
	if u == nil || u.Scheme != "https" || u.User != nil || (u.Port() != "" && u.Port() != "443") {
		return false
	}
	switch strings.ToLower(u.Hostname()) {
	case "api.github.com":
		return u.Path == "/repos/git-for-windows/git/releases/latest"
	case "github.com":
		return strings.HasPrefix(u.Path, "/git-for-windows/git/releases/download/") && !strings.Contains(u.Path, "..")
	case "release-assets.githubusercontent.com":
		return redirect
	default:
		return false
	}
}

func instanceFetchGit(ctx context.Context, raw string, limit int64) ([]byte, error) {
	u, err := url.Parse(raw)
	if err != nil || !instanceGitURLAllowed(u, false) {
		return nil, errors.New("공식 Git for Windows 주소가 아닙니다")
	}
	client := &http.Client{Timeout: 5 * time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) > 5 || !instanceGitURLAllowed(req.URL, true) {
			return errors.New("공식 Git 다운로드의 허용되지 않은 이동입니다")
		}
		return nil
	}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "GeumyiServerCenter personal installer")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("Git 공식 다운로드 HTTP %d", resp.StatusCode)
	}
	if resp.ContentLength > limit {
		return nil, errors.New("Git 다운로드 크기 제한 초과")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, errors.New("Git 다운로드 크기 제한 초과")
	}
	return b, nil
}

func instanceSpigotGit(ctx context.Context, id string) ([]string, error) {
	if git, err := exec.LookPath("git"); err == nil {
		gitDir := filepath.Dir(git)
		if runtime.GOOS != "windows" {
			if _, e := exec.LookPath("sh"); e == nil {
				return []string{gitDir}, nil
			}
		}
		// The normal Git for Windows PATH contains cmd only. BuildTools also needs sh.
		for _, root := range []string{filepath.Dir(gitDir), gitDir} {
			if st, e := os.Stat(filepath.Join(root, "usr", "bin", "sh.exe")); e == nil && !st.IsDir() {
				return []string{gitDir, filepath.Join(root, "bin"), filepath.Join(root, "usr", "bin")}, nil
			}
		}
	}
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" {
		return nil, errors.New("Spigot 빌드에는 Git와 sh가 필요합니다. 자동 Git 준비는 Windows x64를 지원합니다")
	}
	instancePortableGitMu.Lock()
	defer instancePortableGitMu.Unlock()
	instanceInstallUpdate(id, "downloading", "공식 PortableGit 준비 중 · 시스템 Git 설정을 바꾸지 않습니다")
	b, err := instanceFetchGit(ctx, "https://api.github.com/repos/git-for-windows/git/releases/latest", 4<<20)
	if err != nil {
		return nil, err
	}
	var release instanceGitRelease
	if json.Unmarshal(b, &release) != nil || release.Draft || release.Prerelease || !regexp.MustCompile(`^v[0-9][0-9A-Za-z.-]+$`).MatchString(release.Tag) {
		return nil, errors.New("Git 공식 배포 정보를 읽을 수 없습니다")
	}
	for _, asset := range release.Assets {
		if !instancePortableGitAssetRE.MatchString(asset.Name) {
			continue
		}
		if asset.URL != "https://github.com/git-for-windows/git/releases/download/"+release.Tag+"/"+asset.Name || asset.Size <= 0 || asset.Size > 256<<20 {
			return nil, errors.New("PortableGit 공식 파일 정보가 올바르지 않습니다")
		}
		want := parseSHA256Digest(asset.Digest)
		if want == "" {
			for _, sums := range release.Assets {
				if !strings.Contains(strings.ToLower(sums.Name), "sha256") || sums.Size > 1<<20 {
					continue
				}
				if sums.URL != "https://github.com/git-for-windows/git/releases/download/"+release.Tag+"/"+sums.Name {
					continue
				}
				text, e := instanceFetchGit(ctx, sums.URL, 1<<20)
				if e != nil {
					continue
				}
				for _, line := range strings.Split(string(text), "\n") {
					fields := strings.Fields(line)
					if len(fields) == 2 && strings.TrimPrefix(fields[1], "*") == asset.Name {
						want = parseSHA256Digest(fields[0])
					}
				}
			}
		}
		if want == "" {
			return nil, errors.New("PortableGit 공식 SHA-256을 확인하지 못했습니다")
		}
		base := filepath.Join(filepath.Dir(configPath), "tools", "portablegit")
		final := filepath.Join(base, release.Tag)
		if data, e := os.ReadFile(filepath.Join(final, ".gsc-complete.json")); e == nil {
			var marker struct {
				ArchiveSHA string `json:"archive_sha256"`
				GitSHA     string `json:"git_sha256"`
			}
			if json.Unmarshal(data, &marker) == nil && marker.ArchiveSHA == want {
				if got, e := fileSHA256(filepath.Join(final, "bin", "git.exe")); e == nil && got == marker.GitSHA {
					if st, e := os.Stat(filepath.Join(final, "usr", "bin", "sh.exe")); e == nil && !st.IsDir() {
						return []string{filepath.Join(final, "cmd"), filepath.Join(final, "bin"), filepath.Join(final, "usr", "bin")}, nil
					}
				}
			}
			return nil, errors.New("보관된 PortableGit 검증에 실패했습니다. 기존 파일은 덮어쓰지 않았습니다")
		}
		if _, e := os.Lstat(final); !os.IsNotExist(e) {
			return nil, errors.New("PortableGit 폴더가 이미 있어 덮어쓰지 않았습니다")
		}
		if err = os.MkdirAll(base, 0700); err != nil {
			return nil, err
		}
		stage, err := os.MkdirTemp(base, ".prepare-")
		if err != nil {
			return nil, err
		}
		archive, err := instanceFetchGit(ctx, asset.URL, 256<<20)
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(archive)
		if int64(len(archive)) != asset.Size || hex.EncodeToString(sum[:]) != want {
			return nil, errors.New("PortableGit 다운로드 크기 또는 SHA-256이 일치하지 않습니다")
		}
		extractor := filepath.Join(stage, asset.Name)
		if err = writeInstanceNewFile(extractor, archive); err != nil {
			return nil, err
		}
		// Official PortableGit's SFX uses PortableGit under its working directory;
		// it does not honor 7z CLI's -o switch. Keep that directory inside our new stage.
		payload := filepath.Join(stage, "PortableGit")
		cmd := exec.CommandContext(ctx, extractor, "-y", "-gm2", "-nr")
		cmd.Dir = stage
		hideProcess(cmd)
		cmd.Stdout = instanceInstallLog{id}
		cmd.Stderr = cmd.Stdout
		if err = cmd.Run(); err != nil {
			return nil, fmt.Errorf("PortableGit 새 폴더 압축 해제 실패: %w", err)
		}
		git := filepath.Join(payload, "bin", "git.exe")
		sha, err := fileSHA256(git)
		if err != nil {
			return nil, err
		}
		if st, e := os.Stat(filepath.Join(payload, "usr", "bin", "sh.exe")); e != nil || st.IsDir() {
			return nil, errors.New("PortableGit에 필요한 sh 실행 파일이 없습니다")
		}
		marker, _ := json.Marshal(map[string]string{"archive_sha256": want, "git_sha256": sha})
		if err = writeInstanceNewFile(filepath.Join(payload, ".gsc-complete.json"), marker); err != nil {
			return nil, err
		}
		if err = os.Rename(payload, final); err != nil {
			return nil, err
		}
		return []string{filepath.Join(final, "cmd"), filepath.Join(final, "bin"), filepath.Join(final, "usr", "bin")}, nil
	}
	return nil, errors.New("Git 공식 배포에서 PortableGit 64비트 파일을 찾지 못했습니다")
}
