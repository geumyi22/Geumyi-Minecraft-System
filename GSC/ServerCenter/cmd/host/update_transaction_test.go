package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func makeDay9PlanItem(t *testing.T, key, plugin, fromVersion, toVersion, oldPath, cachePath string) updatePlanItem {
	t.Helper()
	return updatePlanItem{
		Key: key,
		Component: testComponentForFile(t, cachePath, plugin, toVersion),
		Installed: PluginInventory{
			File:    filepath.Base(oldPath),
			Name:    plugin,
			Version: fromVersion,
			Enabled: true,
			Managed: true,
		},
	}
}

func TestDay9TransactionFailureInjectionRestoresWholeGroup(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=65530\n"), 0644); err != nil {
		t.Fatal(err)
	}
	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	oldChem := filepath.Join(root, "plugins", "GeumyiChemistry-0.4.1.jar")
	writeTestPluginJar(t, oldTech, "GeumyiTechnology", "0.1.3")
	writeTestPluginJar(t, oldChem, "GeumyiChemistry", "0.4.1")

	cacheDir := t.TempDir()
	newTech := filepath.Join(cacheDir, "GeumyiTechnology-0.1.4.jar")
	newChem := filepath.Join(cacheDir, "GeumyiChemistry-0.4.2.jar")
	writeTestPluginJar(t, newTech, "GeumyiTechnology", "0.1.4")
	writeTestPluginJar(t, newChem, "GeumyiChemistry", "0.4.2")

	plan := []updatePlanItem{
		makeDay9PlanItem(t, "technology", "GeumyiTechnology", "0.1.3", "0.1.4", oldTech, newTech),
		makeDay9PlanItem(t, "chemistry", "GeumyiChemistry", "0.4.1", "0.4.2", oldChem, newChem),
	}
	cachePaths := map[string]string{"technology": newTech, "chemistry": newChem}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65530}

	day9UpdateFaultHook = func(point string) error {
		if strings.HasPrefix(point, "after_activate:0:") {
			return errors.New("injected commit failure")
		}
		return nil
	}
	defer func() { day9UpdateFaultHook = nil }()

	if _, err := applyUpdateTransaction(s, plan, cachePaths, "canary", "day9-test", "abc123"); err == nil {
		t.Fatal("expected injected transaction failure")
	}
	if hasPendingUpdate(s) {
		t.Fatal("successful rollback must clear pending transaction")
	}
	if _, err := os.Stat(oldTech); err != nil {
		t.Fatalf("technology old JAR was not restored: %v", err)
	}
	if _, err := os.Stat(oldChem); err != nil {
		t.Fatalf("chemistry old JAR was not restored: %v", err)
	}
	if name, version := jarPluginInfo(oldTech); name != "GeumyiTechnology" || version != "0.1.3" {
		t.Fatalf("unexpected restored technology metadata %q %q", name, version)
	}
	if name, version := jarPluginInfo(oldChem); name != "GeumyiChemistry" || version != "0.4.1" {
		t.Fatalf("unexpected restored chemistry metadata %q %q", name, version)
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", filepath.Base(newTech))); !os.IsNotExist(err) {
		t.Fatalf("new technology JAR should not remain enabled, err=%v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", filepath.Base(newChem))); !os.IsNotExist(err) {
		t.Fatalf("new chemistry JAR should not remain enabled, err=%v", err)
	}
}

func TestDay9InterruptedAppliedTransactionRollsBackAndRejectsRelease(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=65531\n"), 0644); err != nil {
		t.Fatal(err)
	}
	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	writeTestPluginJar(t, oldTech, "GeumyiTechnology", "0.1.3")

	cacheDir := t.TempDir()
	newTech := filepath.Join(cacheDir, "GeumyiTechnology-0.1.4.jar")
	writeTestPluginJar(t, newTech, "GeumyiTechnology", "0.1.4")

	plan := []updatePlanItem{
		makeDay9PlanItem(t, "technology", "GeumyiTechnology", "0.1.3", "0.1.4", oldTech, newTech),
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65531}

	tx, err := applyUpdateTransaction(s, plan, map[string]string{"technology": newTech}, "canary", "bad-release", "deadbeef")
	if err != nil {
		t.Fatal(err)
	}
	if tx.Phase != "applied_pending_health" || !hasPendingUpdate(s) {
		t.Fatalf("unexpected pending transaction state: %#v", tx)
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", filepath.Base(newTech))); err != nil {
		t.Fatalf("new JAR should be active before recovery: %v", err)
	}

	recovered, err := recoverInterruptedUpdate(s)
	if err != nil {
		t.Fatal(err)
	}
	if !recovered {
		t.Fatal("expected interrupted transaction recovery")
	}
	if hasPendingUpdate(s) {
		t.Fatal("recovery must clear pending transaction")
	}
	if _, err := os.Stat(oldTech); err != nil {
		t.Fatalf("old JAR was not restored: %v", err)
	}
	if name, version := jarPluginInfo(oldTech); name != "GeumyiTechnology" || version != "0.1.3" {
		t.Fatalf("unexpected restored metadata %q %q", name, version)
	}
	if rejected, reason := rejectedUpdateForRelease(s, "bad-release"); !rejected || reason == "" {
		t.Fatalf("failed release should be rejected after recovery, rejected=%v reason=%q", rejected, reason)
	}
}

func TestDay9ValidateUpdatePlanRejectsUnsatisfiedDependency(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=65532\n"), 0644); err != nil {
		t.Fatal(err)
	}
	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	oldGST := filepath.Join(root, "plugins", "GeumyiServerTools-1.1.0.jar")
	writeTestPluginJar(t, oldTech, "GeumyiTechnology", "0.1.3")
	writeTestPluginJar(t, oldGST, "GeumyiServerTools", "1.1.0")

	cacheDir := t.TempDir()
	newTech := filepath.Join(cacheDir, "GeumyiTechnology-0.1.4.jar")
	writeTestPluginJar(t, newTech, "GeumyiTechnology", "0.1.4")

	comp := testComponentForFile(t, newTech, "GeumyiTechnology", "0.1.4")
	comp.Targets = []string{"wild"}
	comp.ReleaseGroup = "server-core"
	comp.Requires = map[string]string{"gst": ">=1.1.1"}

	m := DeploymentManifest{
		Schema: 1, Channel: "canary", Release: "dep-test", Repository: "geumyi22/Geumyi-Minecraft-System",
		Components: map[string]DeploymentComponent{
			"technology": comp,
			"gst": {
				Version: "1.1.1", Kind: "plugin", PluginName: "GeumyiServerTools",
				File: "GeumyiServerTools-1.1.1.jar",
				URL: "https://github.com/example/release/GeumyiServerTools-1.1.1.jar",
				SHA256: strings.Repeat("a", 64), Size: 123, Targets: []string{"wild"},
				ReleaseGroup: "server-core",
			},
		},
	}

	plan := []updatePlanItem{
		{
			Key:       "technology",
			Component: comp,
			Installed: PluginInventory{File: filepath.Base(oldTech), Name: "GeumyiTechnology", Version: "0.1.3", Enabled: true},
		},
	}
	if err := validateUpdatePlan(ServerConfig{ID: "wild", Path: root}, m, plan); err == nil {
		t.Fatal("expected dependency validation failure")
	}
}

func TestDay9VersionRequirements(t *testing.T) {
	cases := []struct {
		version, requirement string
		want                 bool
	}{
		{"1.1.1", ">=1.1.1", true},
		{"1.2.0", ">=1.1.1", true},
		{"1.1.0", ">=1.1.1", false},
		{"0.1.4+113", ">=0.1.4", true},
		{"0.4.1", "=0.4.1", true},
	}
	for _, tc := range cases {
		if got := day9VersionSatisfies(tc.version, tc.requirement); got != tc.want {
			t.Fatalf("%s %s: got %v want %v", tc.version, tc.requirement, got, tc.want)
		}
	}
}
