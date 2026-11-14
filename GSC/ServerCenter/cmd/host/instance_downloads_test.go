package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestInstanceServerDownloadChecksHashSizeAndJar(t *testing.T) {
	var buf bytes.Buffer
	z := zip.NewWriter(&buf)
	f, _ := z.Create("META-INF/MANIFEST.MF")
	_, _ = f.Write([]byte("Manifest-Version: 1.0\n"))
	_ = z.Close()
	b := buf.Bytes()
	sha := sha256.Sum256(b)
	old := sha1.Sum(b)
	md := md5.Sum(b)
	u := "https://fill-data.papermc.io/v1/objects/test/server.jar"
	instanceTestHTTP(t, map[string]string{u: string(b)})
	for _, a := range []instanceServerArtifact{
		{URL: u, SHA256: hex.EncodeToString(sha[:]), Size: int64(len(b))},
		{URL: u, SHA1: hex.EncodeToString(old[:])},
		{URL: u, MD5: hex.EncodeToString(md[:])},
	} {
		if err := downloadInstanceServer(context.Background(), a, filepath.Join(t.TempDir(), "server.jar")); err != nil {
			t.Fatal(err)
		}
	}
	for _, a := range []instanceServerArtifact{
		{URL: u, SHA256: strings.Repeat("0", 64)},
		{URL: u, SHA256: hex.EncodeToString(sha[:]), Size: int64(len(b) + 1)},
		{URL: u},
	} {
		dest := filepath.Join(t.TempDir(), "server.jar")
		if err := downloadInstanceServer(context.Background(), a, dest); err == nil {
			t.Fatal("accepted invalid download")
		}
		if _, err := os.Stat(dest); !os.IsNotExist(err) {
			t.Fatal("failed validation wrote file")
		}
	}
}

func TestInstanceVelocityNewConfiguration(t *testing.T) {
	p := ManagedInstance{Kind: "velocity", MinecraftVersion: "4.3.1", Dir: t.TempDir(), JavaPort: 25577}
	if err := writeInstanceVelocityConfig(&p, "localhost:25565"); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(p.Dir, "velocity.toml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`bind = "0.0.0.0:25577"`, `backend = "localhost:25565"`, `online-mode = true`, `player-info-forwarding-mode = "none"`} {
		if !strings.Contains(string(b), want) {
			t.Fatalf("missing %s", want)
		}
	}
	if err := writeInstanceVelocityConfig(&p, ""); err == nil {
		t.Fatal("overwrote existing config")
	}
	for _, address := range []string{"", "127.0.0.1:25565", "[::1]:25565"} {
		if _, err := validateInstanceBackend(address); err != nil {
			t.Fatal(err)
		}
	}
	for _, address := range []string{"127.0.0.1", "host:0", "host:65536", "evil\"\nkey=true:25565", "host:abc"} {
		if _, err := validateInstanceBackend(address); err == nil {
			t.Fatalf("accepted %q", address)
		}
	}
	for _, address := range []string{"127.0.0.1:25577", "localhost:25577", "[::1]:25577"} {
		if err := validateInstanceProxyDestination(25577, address); err == nil {
			t.Fatal("allowed proxy self-loop")
		}
	}
}

func TestInstanceFillVersionsOnlyStableBuilds(t *testing.T) {
	instanceTestHTTP(t, map[string]string{
		"https://fill.papermc.io/v3/projects/velocity":                       `{"versions":{"4.0":["4.3.2-SNAPSHOT","4.3.1"]}}`,
		"https://fill.papermc.io/v3/projects/velocity/versions/4.3.1/builds": `[{"id":20,"channel":"EXPERIMENTAL","downloads":{"server:default":{"url":"https://fill-data.papermc.io/a.jar"}}},{"id":19,"channel":"STABLE","downloads":{"server:default":{"url":"https://fill-data.papermc.io/b.jar"}}}]`,
	})
	v, err := instanceOfficialVersions(context.Background(), "velocity", "4.3.1")
	if err != nil {
		t.Fatal(err)
	}
	if len(v.Loaders) != 1 || v.Loaders[0] != "19" || v.JavaMajor != 25 {
		t.Fatalf("wrong result %+v", v)
	}
	if len(v.Minecraft) != 1 || v.Minecraft[0] != "4.3.1" {
		t.Fatal("snapshot offered for automatic installation")
	}
	if _, err := instanceDirectArtifact(context.Background(), "velocity", "4.3.1", "20"); err == nil {
		t.Fatal("accepted experimental build")
	}
}

func TestInstanceCreationDefaultsAvoidExistingPortsWithoutCreatingFiles(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	configMu.Lock()
	cfg.Servers = []ServerConfig{{ID: "existing", JavaPort: 25580}}
	configMu.Unlock()
	instanceInstallMu.Lock()
	previous := instanceInstallJobs
	instanceInstallJobs = map[string]*instanceInstallJob{"install": {Phase: "downloading", profile: ManagedInstance{JavaPort: 25581}}}
	instanceInstallMu.Unlock()
	t.Cleanup(func() { instanceInstallMu.Lock(); instanceInstallJobs = previous; instanceInstallMu.Unlock() })
	listener, _ := net.Listen("tcp", ":25582")
	if listener != nil {
		defer listener.Close()
	}
	p := ManagedInstance{ID: "new-server", Kind: "vanilla"}
	if err := applyInstanceCreationDefaults(&p); err != nil {
		t.Fatal(err)
	}
	if p.JavaPort < 25583 || p.JavaPort > 25680 {
		t.Fatalf("selected occupied or excluded port %d", p.JavaPort)
	}
	if p.Dir != filepath.Join(root, "host", "servers", "new-server") {
		t.Fatalf("wrong automatic directory %s", p.Dir)
	}
	if _, err := os.Stat(filepath.Dir(p.Dir)); !os.IsNotExist(err) {
		t.Fatal("defaults wrote filesystem state")
	}
	p.ID = "../existing"
	if err := applyInstanceCreationDefaults(&p); err == nil {
		t.Fatal("accepted path traversal ID")
	}
}

func TestInstanceNewProxyBackendRequiresLoopback(t *testing.T) {
	p := ManagedInstance{JavaPort: 25580}
	ordinary := instanceNewServerProperties(&p)
	if !strings.Contains(ordinary, "online-mode=true\n") || strings.Contains(ordinary, "online-mode=false") {
		t.Fatal("ordinary server authentication disabled")
	}
	p.ProxyBackend = true
	backend := instanceNewServerProperties(&p)
	for _, want := range []string{"server-ip=127.0.0.1\n", "online-mode=false\n", "server-port=25580\n"} {
		if !strings.Contains(backend, want) {
			t.Fatalf("proxy backend missing %s", want)
		}
	}
}

func TestInstanceOfficialServerDownloadsLive(t *testing.T) {
	if os.Getenv("GSC_TEST_OFFICIAL_DOWNLOADS") != "1" {
		t.Skip("set GSC_TEST_OFFICIAL_DOWNLOADS=1 for official server artifact downloads; does not run Java")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
	defer cancel()
	for _, tc := range []struct{ kind, version string }{{"vanilla", "26.3"}, {"paper", "26.3"}, {"purpur", "26.3"}, {"velocity", "4.3.1"}} {
		t.Run(tc.kind, func(t *testing.T) {
			v, err := instanceOfficialVersions(ctx, tc.kind, tc.version)
			if err != nil {
				t.Fatal(err)
			}
			build := ""
			if len(v.Loaders) > 0 {
				build = v.Loaders[0]
			}
			a, err := instanceDirectArtifact(ctx, tc.kind, tc.version, build)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(t.TempDir(), "server.jar")
			if err := downloadInstanceServer(ctx, a, path); err != nil {
				t.Fatal(err)
			}
			st, _ := os.Stat(path)
			t.Log(fmt.Sprintf("%s %s build=%s java=%d verified %d bytes (no JVM started)", tc.kind, tc.version, build, v.JavaMajor, st.Size()))
		})
	}
}
