package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type instanceInstallerTransport func(*http.Request) (*http.Response, error)

func (f instanceInstallerTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func instanceTestHTTP(t *testing.T, bodies map[string]string) {
	t.Helper()
	old := instanceInstallHTTP
	instanceInstallHTTP = &http.Client{Transport: instanceInstallerTransport(func(r *http.Request) (*http.Response, error) {
		body, ok := bodies[r.URL.String()]
		if !ok {
			return nil, fmt.Errorf("unexpected URL %s", r.URL)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header), ContentLength: int64(len(body)), Request: r}, nil
	})}
	t.Cleanup(func() { instanceInstallHTTP = old })
}

func TestInstanceInstallerRejectsUntrustedDownloads(t *testing.T) {
	for _, raw := range []string{"http://meta.fabricmc.net/x", "https://meta.fabricmc.net.evil.test/x", "https://user@meta.fabricmc.net/x", "https://127.0.0.1/x", "https://meta.fabricmc.net:8443/x"} {
		u, _ := url.Parse(raw)
		if validateInstanceDownloadURL(u) == nil {
			t.Fatalf("accepted untrusted URL %s", raw)
		}
	}
	u, _ := url.Parse("https://maven.neoforged.net/releases/a.jar")
	if err := validateInstanceDownloadURL(u); err != nil {
		t.Fatal(err)
	}
}

func TestInstanceNeoVersionMapping(t *testing.T) {
	for version, want := range map[string]string{"20.2.86": "1.20.2", "21.0.12-beta": "1.21", "21.1.266": "1.21.1", "26.1.2.126": "26.1.2", "26.3.0.103": "26.3", "garbage": ""} {
		if got := instanceNeoMinecraft(version); got != want {
			t.Errorf("%s: got %s want %s", version, got, want)
		}
	}
}

func TestInstanceOfficialForgeVersionsFilterByMinecraft(t *testing.T) {
	versionJSON := `{"javaVersion":{"majorVersion":21}}`
	hash := sha1.Sum([]byte(versionJSON))
	instanceTestHTTP(t, map[string]string{
		"https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml": `<metadata><versioning><versions><version>1.20.1-47.4.2</version><version>1.21.1-52.1.21</version><version>1.20.1-47.4.29</version></versions></versioning></metadata>`,
		"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json":              fmt.Sprintf(`{"versions":[{"id":"1.21.1","url":"https://piston-meta.mojang.com/test/version.json","sha1":%q}]}`, hex.EncodeToString(hash[:])),
		"https://piston-meta.mojang.com/test/version.json":                             versionJSON,
	})
	v, err := instanceOfficialVersions(context.Background(), "forge", "1.21.1")
	if err != nil {
		t.Fatal(err)
	}
	if len(v.Loaders) != 1 || v.Loaders[0] != "1.21.1-52.1.21" || v.JavaMajor != 21 {
		t.Fatalf("wrong filtered metadata: %+v", v)
	}
}

func TestInstanceMinecraftMetadataHashMustMatch(t *testing.T) {
	instanceTestHTTP(t, map[string]string{
		"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json": `{"versions":[{"id":"26.3","url":"https://piston-meta.mojang.com/test/version.json","sha1":"0000000000000000000000000000000000000000"}]}`,
		"https://piston-meta.mojang.com/test/version.json":                `{"javaVersion":{"majorVersion":25}}`,
	})
	if _, err := instanceRequiredJava(context.Background(), "26.3"); err == nil {
		t.Fatal("accepted corrupt version metadata")
	}
}

func TestInstanceInstallerRejectsChecksumMismatchBeforeWriting(t *testing.T) {
	instanceTestHTTP(t, map[string]string{
		"https://maven.fabricmc.net/test.jar":        "not-the-signed-checksummed-bytes",
		"https://maven.fabricmc.net/test.jar.sha256": strings.Repeat("0", 64),
	})
	dst := filepath.Join(t.TempDir(), "installer.jar")
	if err := downloadInstanceInstaller(context.Background(), "https://maven.fabricmc.net/test.jar", "https://maven.fabricmc.net/test.jar.sha256", dst); err == nil {
		t.Fatal("accepted mismatched checksum")
	}
	if _, err := os.Stat(dst); !os.IsNotExist(err) {
		t.Fatal("wrote failed installer")
	}
}

func TestInstanceInstallerVerifiedArtifactDoesNotOverwrite(t *testing.T) {
	var b bytes.Buffer
	z := zip.NewWriter(&b)
	f, _ := z.Create("META-INF/MANIFEST.MF")
	_, _ = f.Write([]byte("Manifest-Version: 1.0\n"))
	_ = z.Close()
	hash := sha256.Sum256(b.Bytes())
	instanceTestHTTP(t, map[string]string{"https://maven.fabricmc.net/test.jar": b.String(), "https://maven.fabricmc.net/test.jar.sha256": hex.EncodeToString(hash[:])})
	dst := filepath.Join(t.TempDir(), "installer.jar")
	if err := downloadInstanceInstaller(context.Background(), "https://maven.fabricmc.net/test.jar", "https://maven.fabricmc.net/test.jar.sha256", dst); err != nil {
		t.Fatal(err)
	}
	if err := downloadInstanceInstaller(context.Background(), "https://maven.fabricmc.net/test.jar", "https://maven.fabricmc.net/test.jar.sha256", dst); err == nil {
		t.Fatal("overwrote existing artifact")
	}
}

func TestInstanceFetchBoundsUnknownLength(t *testing.T) {
	instanceTestHTTP(t, map[string]string{"https://meta.fabricmc.net/test": strings.Repeat("a", 50)})
	if _, err := instanceFetch(context.Background(), "https://meta.fabricmc.net/test", 20); err == nil {
		t.Fatal("unbounded download accepted")
	}
}

func TestInstanceCreationRequiresEULA(t *testing.T) {
	r := httptest.NewRequest("POST", "/api/v5/instances/create", strings.NewReader(`{"id":"new","kind":"fabric","eula_accepted":false}`))
	w := httptest.NewRecorder()
	apiInstanceCreate(w, r)
	if w.Code != 400 || !strings.Contains(w.Body.String(), "EULA") {
		t.Fatalf("unexpected response: %d %s", w.Code, w.Body.String())
	}
}

func TestInstanceNewFilesNeverOverwriteWorldOrProperties(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "server.properties")
	want := []byte("server-port=25565\nlevel-name=precious-world\n")
	if err := os.WriteFile(path, want, 0600); err != nil {
		t.Fatal(err)
	}
	if err := writeInstanceNewFile(path, []byte("replaced")); err == nil {
		t.Fatal("overwrote existing settings")
	}
	got, _ := os.ReadFile(path)
	if !bytes.Equal(got, want) {
		t.Fatal("existing data changed")
	}
}

func TestInstanceJavaMajorAndLaunchSelection(t *testing.T) {
	for v, want := range map[string]int{"1.8.0_442": 8, "17.0.13": 17, "21.0.5": 21, "25-ea": 25, "27": 27} {
		if got := instanceJavaMajor(v); got != want {
			t.Errorf("%s: %d != %d", v, got, want)
		}
	}
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "fabric-server-launch.jar"), []byte("test"), 0600)
	p := ManagedInstance{Kind: "fabric", Dir: dir}
	if err := instanceInstalledLaunch(&p); err != nil {
		t.Fatal(err)
	}
	if p.LaunchMode != "jar" || p.LaunchFile != "fabric-server-launch.jar" {
		t.Fatalf("wrong launcher: %+v", p)
	}
}

// Explicitly opt in: normal regression tests remain offline and deterministic.
func TestInstanceOfficialMetadataLive(t *testing.T) {
	if os.Getenv("GSC_TEST_OFFICIAL_META") != "1" {
		t.Skip("official metadata smoke check is opt-in")
	}
	for _, q := range []struct {
		kind, mc string
		java     int
	}{{"fabric", "1.20.1", 17}, {"forge", "1.20.1", 17}, {"neoforge", "1.21.1", 21}, {"neoforge", "26.3", 25}} {
		t.Run(q.kind+"-"+q.mc, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
			defer cancel()
			v, err := instanceOfficialVersions(ctx, q.kind, q.mc)
			if err != nil {
				t.Fatal(err)
			}
			if len(v.Loaders) == 0 || v.JavaMajor != q.java {
				t.Fatalf("unexpected official metadata: %+v", v)
			}
			t.Logf("%s %s: %d loader versions, Java %d", q.kind, q.mc, len(v.Loaders), v.JavaMajor)
		})
	}
}

func TestInstanceInstallBlocksShutdownUntilTerminalState(t *testing.T) {
	instanceInstallMu.Lock()
	oldJobs := instanceInstallJobs
	instanceInstallJobs = map[string]*instanceInstallJob{}
	instanceInstallMu.Unlock()
	t.Cleanup(func() {
		instanceInstallMu.Lock()
		instanceInstallJobs = oldJobs
		instanceInstallMu.Unlock()
	})
	if err := instanceInstallShutdownError(); err != nil {
		t.Fatal(err)
	}
	for _, phase := range []string{"queued", "validating", "downloading", "installing", "registering"} {
		instanceInstallMu.Lock()
		instanceInstallJobs["new-server"] = &instanceInstallJob{ID: "new-server", Phase: phase}
		instanceInstallMu.Unlock()
		if err := instanceInstallShutdownError(); err == nil {
			t.Fatalf("shutdown allowed during %s", phase)
		}
	}
	for _, phase := range []string{"complete", "failed"} {
		instanceInstallUpdate("new-server", phase, "finished")
		if err := instanceInstallShutdownError(); err != nil {
			t.Fatalf("terminal %s blocked shutdown: %v", phase, err)
		}
	}
}

func TestInstanceCreationRejectedDuringShutdownWithoutFilesystemWrites(t *testing.T) {
	old := shuttingDown.Swap(true)
	t.Cleanup(func() { shuttingDown.Store(old) })
	dir := filepath.Join(t.TempDir(), "never-created")
	r := httptest.NewRequest("POST", "/api/v5/instances/create", strings.NewReader(fmt.Sprintf(`{"id":"new","name":"new","kind":"fabric","dir":%q,"eula_accepted":true}`, dir)))
	w := httptest.NewRecorder()
	apiInstanceCreate(w, r)
	if w.Code != http.StatusConflict {
		t.Fatalf("shutdown creation status %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("created filesystem state while shutting down")
	}
}
