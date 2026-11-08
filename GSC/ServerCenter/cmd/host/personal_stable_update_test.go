package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type personalStableTransport struct {
	body     map[string][]byte
	requests int
}

func (transport *personalStableTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	transport.requests++
	body, ok := transport.body[request.URL.String()]
	if !ok {
		return nil, fmt.Errorf("unexpected request in disposable personal release test: %s", request.URL)
	}
	return &http.Response{StatusCode: http.StatusOK, Header: make(http.Header), Body: io.NopCloser(bytes.NewReader(body)), Request: request}, nil
}

func TestPersonalStableGSCOnlyManifestPreservesManagedPluginsAndStartup(t *testing.T) {
	root := t.TempDir()
	previousPath := configPath
	configPath = filepath.Join(root, "server.json")
	t.Cleanup(func() { configPath = previousPath })
	jar := filepath.Join(root, "playground", "plugins", "GeumyiServerTools-1.1.1.jar")
	writeTestPluginJar(t, jar, "GeumyiServerTools", "1.1.1")
	if err := os.WriteFile(filepath.Join(root, "playground", "server.properties"), []byte("server-port=25571\n"), 0600); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(jar)
	if err != nil {
		t.Fatal(err)
	}
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(root, "disposable-public.pem")
	if err = os.WriteFile(key, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}), 0600); err != nil {
		t.Fatal(err)
	}
	manifest := DeploymentManifest{Schema: 1, Channel: "stable", Release: "gsc-v5.0.0", Repository: "geumyi22/Geumyi-Minecraft-System", Components: map[string]DeploymentComponent{
		"gsc": {Version: "5.0.0", Kind: "gsc", Targets: []string{"host"}, File: "GeumyiServerCenter-v5.0.0-Setup.exe", URL: "https://github.com/geumyi22/Geumyi-Minecraft-System/releases/download/gsc-v5.0.0/GeumyiServerCenter-v5.0.0-Setup.exe", SHA256: strings.Repeat("0", 64), Size: 123456},
	}}
	if _, err = selfUpdateComponent(manifest); err != nil {
		t.Fatalf("GSC self updater rejected personal component: %v", err)
	}
	encoded, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	manifestURL := "https://github.com/geumyi22/Geumyi-Minecraft-System/releases/download/gsc-v5.0.0/deployment-stable.json"
	releases, err := json.Marshal([]map[string]any{{"tag_name": "gsc-v5.0.0", "draft": false, "assets": []map[string]string{
		{"name": "deployment-stable.json", "browser_download_url": manifestURL},
		{"name": "deployment-stable.json.sig", "browser_download_url": manifestURL + ".sig"},
	}}})
	if err != nil {
		t.Fatal(err)
	}
	transport := &personalStableTransport{body: map[string][]byte{
		"https://api.github.com/repos/geumyi22/Geumyi-Minecraft-System/releases?per_page=30": releases,
		manifestURL:          encoded,
		manifestURL + ".sig": ed25519.Sign(priv, encoded),
	}}
	previousTransport := http.DefaultTransport
	http.DefaultTransport = transport
	t.Cleanup(func() { http.DefaultTransport = previousTransport })
	configMu.Lock()
	previousConfig := cfg
	cfg = Config{Update: UpdateConfig{Enabled: true, Repository: manifest.Repository, Channel: "stable", PublicKeyPath: key, TimeoutSeconds: 3}}
	configMu.Unlock()
	t.Cleanup(func() { configMu.Lock(); cfg = previousConfig; configMu.Unlock() })
	status := runPreStartUpdater(ServerConfig{ID: "playground", Path: filepath.Join(root, "playground"), UpdatePolicy: serverUpdateManaged})
	if status.Phase != "current" || status.Error != "" || status.BlockStart || len(status.Applied) != 0 || status.Release != manifest.Release {
		t.Fatalf("personal GSC release changed managed server startup: %+v", status)
	}
	if transport.requests != 3 {
		t.Fatalf("unexpected artifact download or missing manifest verification: %d requests", transport.requests)
	}
	after, err := os.ReadFile(jar)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("existing managed plugin changed: %v", err)
	}
}

func TestPersonalStableDefaultChannelPreservesExistingValidChannel(t *testing.T) {
	defaults := defaultUpdateConfig(t.TempDir())
	if defaults.Channel != "stable" || defaults.Enabled {
		t.Fatalf("unexpected new-install update defaults: %+v", defaults)
	}
	for _, channel := range []string{"stable", "beta", "canary"} {
		current := defaults
		current.Channel = channel
		current.Enabled = true
		current.PublicKeyPath = "existing-trusted-key.pem"
		actual := normalizeUpdateConfig(current)
		if actual.Channel != channel || !actual.Enabled || actual.PublicKeyPath != current.PublicKeyPath {
			t.Fatalf("existing update configuration changed: %+v", actual)
		}
	}
}
