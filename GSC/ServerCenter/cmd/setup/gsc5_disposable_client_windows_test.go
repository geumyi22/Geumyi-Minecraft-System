//go:build windows

package main

import (
	"bytes"
	"crypto/sha256"
	"debug/pe"
	"os"
	"path/filepath"
	"testing"
)

// Explicit CI-only opt-in. This exercises the actual client-only doInstall
// logic on an ephemeral Windows Actions runner, not the user's server PC.
// Setup may touch machine-local shortcuts/registry/services; NEVER set this
// opt-in on a personal, remote, or production Windows computer.
func TestGSC5DisposableWindowsClientOnlyInstallation(t *testing.T) {
	if os.Getenv("GSC5_DISPOSABLE_WINDOWS_CLIENT_INSTALL") != "EXPLICIT_CI_ONLY" {
		t.Skip("installer side effects are allowed only on the disposable CI runner")
	}
	// Fail closed if an installed Host might be present on the runner.
	if serviceExists(hostServiceName) || taskExists(hostTaskName) {
		t.Fatal("GSC Host service/task already exists; refusing to touch an existing installation")
	}
	if _, err := os.Stat(filepath.Join(envOr("PROGRAMDATA", `C:\ProgramData`), "GeumyiServerCenter", roleStateFile)); err == nil {
		t.Fatal("existing GSC role state detected; refusing installation test")
	}
	root := t.TempDir()
	for _, name := range []string{"ProgramData", "AppData", "LocalAppData", "UserProfile", "ProgramFiles"} {
		if err := os.MkdirAll(filepath.Join(root, name), 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(filepath.Join(root, "UserProfile", "Desktop"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROGRAMDATA", filepath.Join(root, "ProgramData"))
	t.Setenv("APPDATA", filepath.Join(root, "AppData"))
	t.Setenv("LOCALAPPDATA", filepath.Join(root, "LocalAppData"))
	t.Setenv("USERPROFILE", filepath.Join(root, "UserProfile"))
	t.Setenv("ProgramFiles", filepath.Join(root, "ProgramFiles"))
	installDir := filepath.Join(root, "ProgramFiles", "Geumyi Server Center")

	progressMu.Lock()
	oldProgress := prog
	prog = ProgressState{}
	progressMu.Unlock()
	t.Cleanup(func() {
		progressMu.Lock()
		prog = oldProgress
		progressMu.Unlock()
	})
	// No real server URL, credentials, or network connection is used.
	opt := InstallOptions{
		Role: 2,
		InstallDir: installDir,
		HostURL: "http://127.0.0.1:1",
		Token: "disposable-ci-token-never-production",
		AutoStartClient: false,
		Remote: false,
	}
	doInstall(opt)
	progressMu.RLock()
	first := prog
	progressMu.RUnlock()
	if !first.Done || first.Error != "" || first.Percent != 100 {
		t.Fatalf("client install failed: status=%q done=%v error_present=%v", first.Status, first.Done, first.Error != "")
	}
	clientPath := filepath.Join(installDir, "GeumyiServerCenter.exe")
	installed, err := os.ReadFile(clientPath)
	if err != nil {
		t.Fatalf("client exe absent: %v", err)
	}
	packed, err := payload.ReadFile("payload/GeumyiServerCenter.exe")
	if err != nil || sha256.Sum256(installed) != sha256.Sum256(packed) {
		t.Fatal("installed client does not match embedded original bytes")
	}
	peFile, err := pe.NewFile(bytes.NewReader(installed))
	if err != nil {
		t.Fatalf("client executable is not a PE image: %v", err)
	}
	if peFile.Machine != pe.IMAGE_FILE_MACHINE_AMD64 {
		t.Fatalf("client machine mismatch: 0x%x", peFile.Machine)
	}
	_ = peFile.Close()
	dataDir := filepath.Join(root, "ProgramData", "GeumyiServerCenter")
	state := detectInstalledRole(dataDir, installDir)
	if state != 2 {
		t.Fatalf("installer role state=%d; want client only", state)
	}
	clientCfg := readExistingClientConfig(filepath.Join(root, "AppData", "GeumyiServerCenter", "client.json"))
	if clientCfg.HostURL != opt.HostURL || clientCfg.Token != opt.Token {
		t.Fatal("client configuration was not preserved after protected storage roundtrip")
	}
	if _, err := os.Stat(filepath.Join(installDir, "GeumyiServerHost.exe")); !os.IsNotExist(err) {
		t.Fatal("client-only installer unexpectedly deployed a Host executable")
	}
	// The test deliberately avoids /uninstall to prevent unnecessary global
	// Windows changes. The dedicated GitHub Actions VM is discarded on exit.
	t.Log("DISPOSABLE_GSC5_CLIENT_ONLY_INSTALL_PASS: no Host service or real server contacted")
}
