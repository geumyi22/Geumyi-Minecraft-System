package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDay11SelfUpdateComponentValidation(t *testing.T) {
	good := DeploymentManifest{
		Schema: 1,
		Channel: "canary",
		Release: "test",
		Repository: "geumyi22/Geumyi-Minecraft-System",
		Components: map[string]DeploymentComponent{
			"gsc": {
				Version: "4.3.0",
				Kind: "gsc",
				File: "GeumyiServerCenter-v4.3.0-Setup.exe",
				URL: "https://github.com/example/release/GeumyiServerCenter-v4.3.0-Setup.exe",
				SHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
				Size: 123456,
				Targets: []string{"host"},
				RequiresRestart: true,
			},
		},
	}
	comp, err := selfUpdateComponent(good)
	if err != nil {
		t.Fatal(err)
	}
	if comp.Version != "4.3.0" || comp.Kind != "gsc" {
		t.Fatalf("unexpected component: %+v", comp)
	}

	badTarget := good
	badTarget.Components = map[string]DeploymentComponent{"gsc": comp}
	x := badTarget.Components["gsc"]
	x.Targets = []string{"wild"}
	badTarget.Components["gsc"] = x
	if _, err := selfUpdateComponent(badTarget); err == nil {
		t.Fatal("non-host GSC target accepted")
	}

	badFile := good
	badFile.Components = map[string]DeploymentComponent{"gsc": comp}
	x = badFile.Components["gsc"]
	x.File = "../evil.exe"
	badFile.Components["gsc"] = x
	if _, err := selfUpdateComponent(badFile); err == nil {
		t.Fatal("unsafe self-update file accepted")
	}
}

func TestDay11SelfUpdateStagePathStaysUnderGSCStaging(t *testing.T) {
	oldConfigPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldConfigPath }()

	comp := DeploymentComponent{
		File: "GeumyiServerCenter-v4.3.0-Setup.exe",
	}
	got := selfUpdateStagePath("../release", comp)
	wantRoot := filepath.Join(v4Root(), "Staging", "GSC")
	rel, err := filepath.Rel(wantRoot, got)
	if err != nil {
		t.Fatal(err)
	}
	if rel == ".." || len(rel) >= 3 && rel[:3] == ".."+string(filepath.Separator) {
		t.Fatalf("stage path escaped root: %s", got)
	}
}


func TestDay11SelfUpdateLaunchLockRejectsConcurrentAndRecoversStale(t *testing.T) {
	oldConfigPath := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = oldConfigPath }()

	if err := reserveGSCSelfUpdateLaunch("4.3.0"); err != nil {
		t.Fatal(err)
	}
	lock := gscSelfUpdateLockPath()
	defer os.Remove(lock)
	if err := reserveGSCSelfUpdateLaunch("4.3.0"); err == nil {
		t.Fatal("concurrent self-update launch lock was accepted")
	}
	old := time.Now().Add(-20 * time.Minute)
	if err := os.Chtimes(lock, old, old); err != nil {
		t.Fatal(err)
	}
	if err := reserveGSCSelfUpdateLaunch("4.3.0"); err != nil {
		t.Fatalf("stale self-update lock was not recovered: %v", err)
	}
}


func TestDay11GSCVersionComparisonBlocksDowngrade(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"4.3.7", "4.3.7", 0},
		{"4.3.5", "4.3.7", -1},
		{"4.3.7", "4.3.6", 1},
		{"4.10.0", "4.9.9", 1},
		{"v4.3.7", "4.3.7+119", 0},
	}
	for _, tc := range cases {
		got, err := compareGSCVersions(tc.a, tc.b)
		if err != nil {
			t.Fatalf("%s vs %s: %v", tc.a, tc.b, err)
		}
		if got != tc.want {
			t.Fatalf("%s vs %s: got %d want %d", tc.a, tc.b, got, tc.want)
		}
	}
	if err := requireNewerGSCVersion("4.3.4"); err == nil {
		t.Fatal("older signed release was accepted as self-update target")
	}
	if err := requireNewerGSCVersion("4.3.5"); err == nil {
		t.Fatal("older signed release was accepted as self-update target")
	}
	if err := requireNewerGSCVersion("4.3.7"); err == nil {
		t.Fatal("same version was accepted as self-update target")
	}
	if err := requireNewerGSCVersion("4.3.7"); err != nil {
		t.Fatalf("newer version was rejected: %v", err)
	}
}
