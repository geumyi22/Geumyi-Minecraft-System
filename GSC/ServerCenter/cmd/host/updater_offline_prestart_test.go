package main

import (
	"bytes"
	"os"
	"path/filepath"
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
