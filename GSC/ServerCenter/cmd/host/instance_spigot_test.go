package main

import (
	"context"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestInstanceSpigotOfficialVersions(t *testing.T) {
	instanceTestHTTP(t, map[string]string{
		"https://hub.spigotmc.org/versions/":            `<a href="1.21.1.json">a</a><a href="26.3.json">b</a><a href="../26.4.json">c</a><a href="latest.json">latest</a><a href="1.21.1.json">duplicate</a>`,
		"https://hub.spigotmc.org/versions/1.21.1.json": `{"name":"4344","refs":{"Spigot":"a759b629cbf86401aab56b8c3f21a635e9e76c15"},"toolsVersion":181,"javaVersions":[65,67]}`,
	})
	got, err := instanceSpigotVersions(context.Background(), "1.21.1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Minecraft) != 2 || got.Minecraft[0] != "26.3" || len(got.Loaders) != 1 || got.Loaders[0] != "4344" || got.JavaMajor != 21 {
		t.Fatalf("unexpected versions: %+v", got)
	}
	if _, err = instanceSpigotVersions(context.Background(), "../1.21.1"); err == nil {
		t.Fatal("accepted path traversal as version")
	}
}

func TestInstanceSpigotRejectsNewerBuildToolsAndBadJavaMetadata(t *testing.T) {
	for name, body := range map[string]string{
		"tools": `{"name":"5000","refs":{"Spigot":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"toolsVersion":999,"javaVersions":[65,67]}`,
		"java":  `{"name":"5000","refs":{"Spigot":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"toolsVersion":181,"javaVersions":[67,65]}`,
		"ref":   `{"name":"5000","refs":{"Spigot":"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"},"toolsVersion":181,"javaVersions":[65,67]}`,
	} {
		t.Run(name, func(t *testing.T) {
			instanceTestHTTP(t, map[string]string{"https://hub.spigotmc.org/versions/1.21.1.json": body})
			if _, err := instanceReadSpigotManifest(context.Background(), "1.21.1"); err == nil {
				t.Fatal("accepted invalid official metadata")
			}
		})
	}
}

func TestInstanceSpigotRefusesExistingServerDirectory(t *testing.T) {
	p := ManagedInstance{ID: "spigot", Dir: t.TempDir(), Kind: "spigot"}
	marker, _ := json.Marshal(map[string]string{"instance_id": p.ID, "job_id": "job", "kind": "spigot"})
	if err := os.WriteFile(filepath.Join(p.Dir, ".gsc-install.json"), marker, 0600); err != nil {
		t.Fatal(err)
	}
	if err := instanceSpigotFreshDirectory("job", p); err != nil {
		t.Fatal(err)
	}
	if err := instanceSpigotFreshDirectory("other-job", p); err == nil {
		t.Fatal("accepted another install job")
	}
	world := filepath.Join(p.Dir, "world")
	if err := os.Mkdir(world, 0700); err != nil {
		t.Fatal(err)
	}
	if err := instanceSpigotFreshDirectory("job", p); err == nil {
		t.Fatal("accepted existing world directory")
	}
	if _, err := os.Stat(world); err != nil {
		t.Fatal("world changed")
	}
}

func TestInstanceSpigotGitURLsAreRepositoryScoped(t *testing.T) {
	for _, raw := range []string{"http://github.com/git-for-windows/git/releases/download/v1/a", "https://github.com/other/repo/releases/download/v1/a", "https://api.github.com/repos/other/git/releases/latest", "https://github.com/git-for-windows/git/releases/download/../a", "https://github.com.evil.test/git-for-windows/git/releases/download/v1/a", "https://user@github.com/git-for-windows/git/releases/download/v1/a", "https://127.0.0.1/a"} {
		u, _ := url.Parse(raw)
		if instanceGitURLAllowed(u, false) {
			t.Errorf("accepted %s", raw)
		}
	}
	u, _ := url.Parse("https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/PortableGit-2.56.1-64-bit.7z.exe")
	if !instanceGitURLAllowed(u, false) {
		t.Fatal("rejected official Git asset")
	}
	u, _ = url.Parse("https://release-assets.githubusercontent.com/asset")
	if instanceGitURLAllowed(u, false) || !instanceGitURLAllowed(u, true) {
		t.Fatal("asset CDN allowed as initial URL")
	}
}

func TestInstanceSpigotBuildEnvironmentIsLocal(t *testing.T) {
	t.Setenv("MAVEN_OPTS", "-Duser.home=outside")
	t.Setenv("JAVA_TOOL_OPTIONS", "-javaagent:outside.jar")
	t.Setenv("GIT_DIR", "outside")
	t.Setenv("GIT_CONFIG_COUNT", "1")
	env := instanceSpigotBuildEnv(filepath.Join(t.TempDir(), "bin", "java.exe"), []string{filepath.Join(t.TempDir(), "git")}, "C:/new/cache/home", "C:/new/cache/m2", "C:/new/cache/gitconfig")
	joined := strings.Join(env, "\n")
	if strings.Contains(joined, "outside") || !strings.Contains(joined, "GIT_CONFIG_GLOBAL=C:/new/cache/gitconfig") || !strings.Contains(joined, `-Dmaven.repo.local="C:/new/cache/m2"`) {
		t.Fatal("build environment retained external overrides or omitted private cache settings")
	}
}

func TestInstanceProxyManagedModeNeverUsesScheduler(t *testing.T) {
	if _, err := instanceProxyTarget(ManagedInstance{Kind: "velocity", ManagementMode: "gsc"}); err == nil {
		t.Fatal("GSC-owned proxy entered Scheduler path")
	}
}

// Explicit opt-in only: downloads and extracts the official Git tool into a new QA directory.
// This never changes system PATH, Git registration, task definitions or Minecraft servers.
func TestInstanceSpigotLivePortableGit(t *testing.T) {
	dir := os.Getenv("GSC_SPIGOT_LIVE_GIT_DIR")
	if dir == "" {
		t.Skip("set GSC_SPIGOT_LIVE_GIT_DIR to a new QA directory to exercise official Git preparation")
	}
	if runtime.GOOS != "windows" {
		t.Skip("Windows portable Git")
	}
	if _, err := os.Lstat(dir); !os.IsNotExist(err) {
		t.Fatal("live Git QA requires a new directory")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	old := configPath
	configPath = filepath.Join(dir, "server.json")
	t.Cleanup(func() { configPath = old })
	t.Setenv("PATH", filepath.Join(os.Getenv("SystemRoot"), "System32"))
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Minute)
	defer cancel()
	dirs, err := instanceSpigotGit(ctx, "live-git-qa")
	if err != nil {
		t.Fatal(err)
	}
	if len(dirs) != 3 {
		t.Fatalf("wrong Git runtime directories: %v", dirs)
	}
	t.Logf("Official PortableGit prepared: %s", dirs[0])
}

// Exercises the actual installation helper, including manifest, artifact checksum,
// Git discovery, local caches and output validation. Never launches Minecraft.
func TestInstanceSpigotLiveBuild(t *testing.T) {
	dir := os.Getenv("GSC_SPIGOT_LIVE_BUILD_DIR")
	if dir == "" {
		t.Skip("set GSC_SPIGOT_LIVE_BUILD_DIR to a new QA directory")
	}
	java := os.Getenv("GSC_SPIGOT_LIVE_JAVA")
	if java == "" {
		t.Fatal("GSC_SPIGOT_LIVE_JAVA must name a compatible Java executable")
	}
	if _, err := os.Lstat(dir); !os.IsNotExist(err) {
		t.Fatal("live BuildTools QA requires a new directory")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	p := ManagedInstance{ID: "spigot-live-qa", Kind: "spigot", Dir: dir, JavaPath: java, MinecraftVersion: "1.21.1", LoaderVersion: "4344"}
	job := "spigot-live-qa"
	marker, _ := json.Marshal(map[string]string{"instance_id": p.ID, "job_id": job, "kind": "spigot"})
	if err := writeInstanceNewFile(filepath.Join(dir, ".gsc-install.json"), marker); err != nil {
		t.Fatal(err)
	}
	old := configPath
	configPath = filepath.Join(dir, "..", "spigot-qa-config", "server.json")
	t.Cleanup(func() { configPath = old })
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Minute)
	defer cancel()
	if err := installInstanceSpigot(ctx, job, &p); err != nil {
		t.Fatal(err)
	}
	if p.LaunchMode != "jar" || p.LaunchFile != "server.jar" {
		t.Fatalf("invalid launch output: %+v", p)
	}
	if _, err := os.Stat(filepath.Join(dir, "eula.txt")); !os.IsNotExist(err) {
		t.Fatal("build helper wrote EULA unexpectedly")
	}
	t.Logf("Actual BuildTools installation complete: %s", filepath.Join(dir, p.LaunchFile))
}

func TestInstanceSpigotLiveSourceVerification(t *testing.T) {
	dir := os.Getenv("GSC_SPIGOT_LIVE_VERIFY_DIR")
	if dir == "" {
		t.Skip("set GSC_SPIGOT_LIVE_VERIFY_DIR to an existing QA BuildTools directory")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	m, err := instanceReadSpigotManifest(ctx, "1.21.1")
	if err != nil {
		t.Fatal(err)
	}
	dirs, err := instanceSpigotGit(ctx, "read-only-build-qa")
	if err != nil {
		t.Fatal(err)
	}
	if err = instanceSpigotVerifyRefs(ctx, dir, dirs, os.Environ(), m); err != nil {
		t.Fatal(err)
	}
	m.Refs["Spigot"] = strings.Repeat("0", 40)
	if err = instanceSpigotVerifyRefs(ctx, dir, dirs, os.Environ(), m); err == nil {
		t.Fatal("accepted a different Spigot source revision")
	}
}
