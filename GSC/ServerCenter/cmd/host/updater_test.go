package main

import (
	"archive/zip"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTestPluginJar(t *testing.T, path, name, version string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	z := zip.NewWriter(f)
	w, err := z.Create("plugin.yml")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("name: " + name + "\nversion: " + version + "\n")); err != nil {
		t.Fatal(err)
	}
	if err := z.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}

func testComponentForFile(t *testing.T, path, name, version string) DeploymentComponent {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(b)
	return DeploymentComponent{
		Version:    version,
		Kind:       "plugin",
		PluginName: name,
		File:       filepath.Base(path),
		URL:        "https://github.com/example/release/" + filepath.Base(path),
		SHA256:     hex.EncodeToString(sum[:]),
		Size:       int64(len(b)),
		Targets:    []string{"wild"},
	}
}

func TestLoadDeploymentPublicKeyEd25519(t *testing.T) {
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(t.TempDir(), "deployment-public.pem")
	if err := os.WriteFile(p, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := loadDeploymentPublicKey(p)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(pub) {
		t.Fatal("loaded public key differs")
	}
}

func TestBuildUpdatePlanUpdatesInstalledGeumyiPluginOnly(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=25565\n"), 0644); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	writeTestPluginJar(t, old, "GeumyiTechnology", "0.1.3")

	m := DeploymentManifest{Schema: 1, Channel: "canary", Release: "test", Components: map[string]DeploymentComponent{
		"technology": {
			Version: "0.1.4", Kind: "plugin", PluginName: "GeumyiTechnology",
			File: "GeumyiTechnology-0.1.4.jar", URL: "https://github.com/example/release/GeumyiTechnology-0.1.4.jar",
			SHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			Size: 123, Targets: []string{"wild"},
		},
		"chemistry": {
			Version: "0.4.2", Kind: "plugin", PluginName: "GeumyiChemistry",
			File: "GeumyiChemistry-0.4.2.jar", URL: "https://github.com/example/release/GeumyiChemistry-0.4.2.jar",
			SHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			Size: 123, Targets: []string{"wild"},
		},
	}}
	plan, err := buildUpdatePlan(ServerConfig{ID: "wild", Path: root}, m)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan) != 1 || plan[0].Component.PluginName != "GeumyiTechnology" {
		t.Fatalf("unexpected plan: %#v", plan)
	}
}

func TestReplaceManagedPluginPreStartKeepsPreviousCopy(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=25565\n"), 0644); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	writeTestPluginJar(t, old, "GeumyiTechnology", "0.1.3")

	cache := filepath.Join(t.TempDir(), "GeumyiTechnology-0.1.4.jar")
	writeTestPluginJar(t, cache, "GeumyiTechnology", "0.1.4")
	comp := testComponentForFile(t, cache, "GeumyiTechnology", "0.1.4")
	item := updatePlanItem{
		Key: "technology",
		Component: comp,
		Installed: PluginInventory{File: filepath.Base(old), Name: "GeumyiTechnology", Version: "0.1.3", Enabled: true, Managed: true},
	}
	s := ServerConfig{ID: "wild", Path: root}
	if err := replaceManagedPluginPreStart(s, item, cache); err != nil {
		t.Fatal(err)
	}
	newPath := filepath.Join(root, "plugins", filepath.Base(cache))
	if _, err := os.Stat(newPath); err != nil {
		t.Fatalf("new plugin missing: %v", err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatalf("old enabled plugin should be removed, err=%v", err)
	}
	backup := filepath.Join(root, ".geumyi-update", "previous", "GeumyiTechnology.jar.previous")
	if _, err := os.Stat(backup); err != nil {
		t.Fatalf("previous copy missing: %v", err)
	}
	name, version := jarPluginInfo(newPath)
	if name != "GeumyiTechnology" || version != "0.1.4" {
		t.Fatalf("unexpected installed plugin metadata %s %s", name, version)
	}
}

func TestTargetIncludes(t *testing.T) {
	if !targetIncludes([]string{"wild"}, "wild") {
		t.Fatal("wild target should match")
	}
	if !targetIncludes([]string{"*"}, "playground") {
		t.Fatal("wildcard target should match")
	}
	if targetIncludes([]string{"wild"}, "playground") {
		t.Fatal("different server target must not match")
	}
}

func TestDay10UpdateDecisionMapsToSafePolicies(t *testing.T) {
	tests := []struct {
		choice string
		want string
		ok bool
	}{
		{"defer", serverUpdateHold, true},
		{"manual", serverUpdateManual, true},
		{"enable-managed", serverUpdateManaged, true},
		{"  DEFER  ", serverUpdateHold, true},
		{"restart-now", "", false},
		{"", "", false},
	}
	for _, tc := range tests {
		got, ok := updatePolicyForDecision(tc.choice)
		if got != tc.want || ok != tc.ok {
			t.Fatalf("decision %q: policy=%q ok=%v want=%q ok=%v", tc.choice, got, ok, tc.want, tc.ok)
		}
	}
}

func TestDay10OtherReceivesWildTechnologyChemistryTargets(t *testing.T) {
	targets := []string{"wild", "other"}
	if !targetIncludesServer(targets, ServerConfig{ID:"other", Role:serverRoleOther}) ||
		!targetIncludesServer(targets, ServerConfig{ID:"wild", Role:serverRoleWild}) {
		t.Fatal("Technology/Chemistry must target both Wild and Other")
	}
	for _, id := range []string{"lobby", "playground"} {
		if targetIncludesServer(targets, ServerConfig{ID:id}) {
			t.Fatalf("Technology/Chemistry target leaked into %s", id)
		}
	}
}

func TestDay11UpdateRestartSafetyBlocksOnlinePlayers(t *testing.T) {
	tests := []struct {
		online  bool
		players int
		blocked bool
		safe    bool
	}{
		{false, 0, false, true},
		{true, 0, false, true},
		{true, 1, true, false},
		{true, 5, true, false},
	}
	for _, tc := range tests {
		blocked, safe := updateRestartSafety(tc.online, tc.players)
		if blocked != tc.blocked || safe != tc.safe {
			t.Fatalf("online=%v players=%d => blocked=%v safe=%v want blocked=%v safe=%v",
				tc.online, tc.players, blocked, safe, tc.blocked, tc.safe)
		}
	}
}

func TestDay11UpdateDryRunNeverInstallsOrRestarts(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	oldJar := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	writeTestPluginJar(t, oldJar, "GeumyiTechnology", "0.1.3")

	manifest := DeploymentManifest{
		Schema: 1,
		Channel: "canary",
		Release: "test-day11",
		Repository: "geumyi22/Geumyi-Minecraft-System",
		Components: map[string]DeploymentComponent{
			"technology": {
				Version: "0.1.4",
				Kind: "plugin",
				PluginName: "GeumyiTechnology",
				File: "GeumyiTechnology-0.1.4.jar",
				URL: "https://github.com/example/release/GeumyiTechnology-0.1.4.jar",
				SHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
				Size: 123,
				Targets: []string{"wild"},
				RequiresRestart: true,
			},
		},
	}

	configMu.Lock()
	oldCfg := cfg
	cfg = Config{
		Update: UpdateConfig{Enabled: true, Repository: "geumyi22/Geumyi-Minecraft-System", Channel: "canary", TimeoutSeconds: 12},
		Servers: []ServerConfig{{
			ID: "wild", Name: "Wild", Role: serverRoleWild, Path: root,
			JavaPort: 0, RCONPort: 0, BedrockPort: 0, GDSAPIPort: 0,
			UpdatePolicy: serverUpdateManaged,
		}},
	}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	result := buildUpdateDryRun(cfg.Update, manifest, "abc123", manifest.Release, "wild")
	if !result.DryRun || result.InstallPerformed || result.RestartPerformed {
		t.Fatalf("dry-run mutation flags wrong: %+v", result)
	}
	if !result.SignatureVerified || result.Release != "test-day11" || result.ManifestSHA256 != "abc123" {
		t.Fatalf("dry-run provenance wrong: %+v", result)
	}
	if len(result.Servers) != 1 || len(result.Servers[0].Items) != 1 {
		t.Fatalf("unexpected dry-run plan: %+v", result)
	}
	item := result.Servers[0].Items[0]
	if item.PluginName != "GeumyiTechnology" || item.InstalledVersion != "0.1.3" || item.TargetVersion != "0.1.4" {
		t.Fatalf("unexpected item: %+v", item)
	}
	if result.Servers[0].PlayerAwareBlock || !result.Servers[0].RestartSafe {
		t.Fatalf("offline test server should be restart-safe: %+v", result.Servers[0])
	}
	if _, err := os.Stat(oldJar); err != nil {
		t.Fatalf("dry-run changed installed plugin: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", "GeumyiTechnology-0.1.4.jar")); !os.IsNotExist(err) {
		t.Fatalf("dry-run created target artifact, err=%v", err)
	}
}


func TestDay11PerServerUpdateChannelNormalization(t *testing.T) {
	tests := map[string]string{
		"": serverUpdateChannelInherit,
		"inherit": serverUpdateChannelInherit,
		" STABLE ": serverUpdateChannelStable,
		"beta": serverUpdateChannelBeta,
		"CANARY": serverUpdateChannelCanary,
		"invalid": serverUpdateChannelInherit,
	}
	for input, want := range tests {
		if got := normalizeServerUpdateChannel(input); got != want {
			t.Fatalf("channel %q => %q, want %q", input, got, want)
		}
	}
}

func TestDay11PerServerUpdateChannelOverridesGlobal(t *testing.T) {
	configMu.Lock()
	oldCfg := cfg
	cfg = Config{Update: UpdateConfig{
		Enabled: true,
		Repository: "geumyi22/Geumyi-Minecraft-System",
		Channel: "stable",
		TimeoutSeconds: 12,
	}}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	if got := effectiveUpdateConfigForServer(ServerConfig{ID: "wild", UpdateChannel: "beta"}).Channel; got != "beta" {
		t.Fatalf("server beta override => %q", got)
	}
	if got := effectiveUpdateConfigForServer(ServerConfig{ID: "wild", UpdateChannel: "inherit"}).Channel; got != "stable" {
		t.Fatalf("inherit should use global stable, got %q", got)
	}
}

func TestDay11UpdatePinNormalization(t *testing.T) {
	s := normalizeServerConfig(ServerConfig{ID: "wild", UpdatePin: "  release-2026.10.04  "})
	if s.UpdatePin != "release-2026.10.04" {
		t.Fatalf("unexpected pin normalization: %q", s.UpdatePin)
	}
	long := strings.Repeat("x", 150)
	s = normalizeServerConfig(ServerConfig{ID: "wild", UpdatePin: long})
	if len(s.UpdatePin) != 128 {
		t.Fatalf("pin length=%d want=128", len(s.UpdatePin))
	}
}
