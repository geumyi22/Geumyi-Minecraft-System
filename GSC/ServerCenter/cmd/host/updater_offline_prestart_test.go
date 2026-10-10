package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// This exercises the pre-start updater decision on a disposable directory.
// It does not launch Paper, operate on the user's server, or simulate an
// actual unplugged network. It protects the narrower requirement that a
// local release-verification failure must not destroy the known-good JAR.
func TestDay12PreStartMissingTrustedKeyFailsOpenWithOriginalPlugin(t *testing.T) {
	root := t.TempDir()
	oldJar := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.4.jar")
	writeTestPluginJar(t, oldJar, "GeumyiTechnology", "0.1.4")
	before, err := os.ReadFile(oldJar)
	if err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	previous := cfg
	cfg = Config{
		Update: UpdateConfig{
			Enabled: true,
			Repository: "geumyi22/Geumyi-Minecraft-System",
			Channel: "beta",
			PublicKeyPath: filepath.Join(root, "missing-pinned-trusted-key.pem"),
			TimeoutSeconds: 3,
		},
	}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = previous
		configMu.Unlock()
	}()

	s := ServerConfig{
		ID: "day12-disposable-wild",
		Name: "Day12Disposable",
		Path: root,
		UpdatePolicy: serverUpdateManaged,
	}
	status := runPreStartUpdater(s)
	if status.BlockStart {
		t.Fatalf("missing trusted release key blocked startup despite no incomplete transaction: %+v", status)
	}
	if status.Phase != "error" || status.Error == "" {
		t.Fatalf("missing trusted key should report a warning/error, not claim updated: %+v", status)
	}
	if len(status.Applied) > 0 {
		t.Fatalf("missing trusted key applied an update: %+v", status)
	}
	after, err := os.ReadFile(oldJar)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("pre-start verification error changed known-good plugin: %v", err)
	}
}

func TestDay12PreStartExplicitHoldAndManualPreserveInstalledJar(t *testing.T) {
	for _, policy := range []string{serverUpdateHold, serverUpdateManual} {
		t.Run(policy, func(t *testing.T) {
			root := t.TempDir()
			oldJar := filepath.Join(root, "plugins", "GeumyiChemistry-0.4.1.jar")
			writeTestPluginJar(t, oldJar, "GeumyiChemistry", "0.4.1")
			before, err := os.ReadFile(oldJar)
			if err != nil { t.Fatal(err) }

			configMu.Lock()
			previous := cfg
			cfg = Config{Update: UpdateConfig{
				Enabled: true,
				Repository: "geumyi22/Geumyi-Minecraft-System",
				Channel: "stable",
				PublicKeyPath: filepath.Join(root, "missing-key.pem"),
				TimeoutSeconds: 3,
			}}
			configMu.Unlock()
			defer func(){
				configMu.Lock()
				cfg = previous
				configMu.Unlock()
			}()

			status := runPreStartUpdater(ServerConfig{
				ID: "day12-disposable-"+policy, Path: root, UpdatePolicy: policy,
			})
			expected := "held"
			if policy == serverUpdateManual { expected = "manual" }
			if status.Phase != expected || status.BlockStart || len(status.Applied) != 0 {
				t.Fatalf("explicit %s should preserve startup and installed files: %+v", policy, status)
			}
			after, err := os.ReadFile(oldJar)
			if err != nil || !bytes.Equal(before,after) {
				t.Fatalf("explicit %s modified installed jar: %v", policy, err)
			}
		})
	}
}

type day12RefuseGitHubNetwork struct{ requests int }
func (rt *day12RefuseGitHubNetwork) RoundTrip(r *http.Request) (*http.Response, error) {
	rt.requests++
	if r.URL.Host != "api.github.com" || r.URL.Scheme != "https" {
		return nil, errors.New("unexpected external URL requested in offline-source fixture")
	}
	return nil, errors.New("disposable fixture: update source unreachable")
}

// Phase 12.7 genuinely exercises an unavailable update HTTP transport at the
// GSC pre-start call site (instead of a missing key). All HTTP attempts are
// intercepted, and all writes remain within Go's temporary test directories.
// This is not production server/Paper boot or an actual LAN/Internet outage.
func TestDay12PreStartNetworkUnavailableDoesNotOverwriteKnownGoodPlugin(t *testing.T) {
	root := t.TempDir()
	oldConfigPath := configPath
	configPath = filepath.Join(root, "server.json")
	defer func() { configPath = oldConfigPath }()

	jar := filepath.Join(root, "playground", "plugins", "GeumyiServerTools-1.1.1.jar")
	writeTestPluginJar(t, jar, "GeumyiServerTools", "1.1.1")
	before, err := os.ReadFile(jar)
	if err != nil { t.Fatal(err) }

	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil { t.Fatal(err) }
	keyBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil { t.Fatal(err) }
	keyFile := filepath.Join(root, "disposable-public.pem")
	if err := os.WriteFile(keyFile, pem.EncodeToMemory(&pem.Block{
		Type: "PUBLIC KEY", Bytes: keyBytes,
	}), 0600); err != nil { t.Fatal(err) }

	transport := &day12RefuseGitHubNetwork{}
	oldTransport := http.DefaultTransport
	http.DefaultTransport = transport
	defer func() { http.DefaultTransport = oldTransport }()

	configMu.Lock()
	oldCfg := cfg
	cfg = Config{Update: UpdateConfig{
		Enabled: true, Repository: "geumyi22/Geumyi-Minecraft-System",
		Channel: "beta", PublicKeyPath: keyFile, TimeoutSeconds: 3,
	}}
	configMu.Unlock()
	defer func(){
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	status := runPreStartUpdater(ServerConfig{
		ID: "day12-disposable-playground",
		Path: filepath.Join(root, "playground"),
		UpdatePolicy: serverUpdateManaged,
	})
	if transport.requests != 1 {
		t.Fatalf("expected one intercepted remote metadata attempt; got %d", transport.requests)
	}
	if status.Phase != "error" || status.BlockStart || len(status.Applied) != 0 {
		t.Fatalf("network-source failure must keep prior plugin and permit normal startup path: %+v", status)
	}
	if !strings.Contains(status.Error, "update source unreachable") {
		t.Fatalf("failure was not caused by the intercepted offline source: %q", status.Error)
	}
	after, err := os.ReadFile(jar)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("disposable network-source failure modified original plugin: %v", err)
	}
}
