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

// This runs only AFTER build.ps1 has produced the actual Windows Host and
// Client payloads. No installer is launched and no Windows services, tasks,
// registry entries, worlds, or real installation files are touched.
func TestGSC5RealPackagedPayloadExtractAndRollback(t *testing.T) {
	if os.Getenv("GSC5_REAL_PAYLOAD_TEST") != "1" {
		t.Skip("actual compiled payload fixtures are staged only after build.ps1")
	}
	if version != "5.0.0-beta.1" {
		t.Fatalf("unexpected setup version %q", version)
	}

	root := t.TempDir()
	installed := filepath.Join(root, "disposable-installed")
	backups := filepath.Join(root, "disposable-backup")
	for _, name := range []string{"GeumyiServerHost.exe", "GeumyiServerCenter.exe"} {
		t.Run(name, func(t *testing.T) {
			embedded, err := payload.ReadFile("payload/" + name)
			if err != nil {
				t.Fatal(err)
			}
			compiled, err := os.ReadFile(filepath.Join("payload", name))
			if err != nil || !bytes.Equal(embedded, compiled) {
				t.Fatalf("embedded payload differs from compiled source: %v", err)
			}
			if len(embedded) < 100000 {
				t.Fatalf("real %s payload too small: %d", name, len(embedded))
			}
			image, err := pe.NewFile(bytes.NewReader(embedded))
			if err != nil {
				t.Fatalf("%s is not a valid Windows PE image: %v", name, err)
			}
			if image.Machine != pe.IMAGE_FILE_MACHINE_AMD64 {
				t.Fatalf("%s machine is 0x%x, expected x64", name, image.Machine)
			}
			_ = image.Close()

			target := filepath.Join(installed, name)
			if err := writeEmbeddedStrict(name, target); err != nil {
				t.Fatal(err)
			}
			actual, err := os.ReadFile(target)
			if err != nil || sha256.Sum256(actual) != sha256.Sum256(embedded) {
				t.Fatal("extracted payload is not byte-identical")
			}

			saved, err := backupSelfUpdateFile(target, backups)
			if err != nil || !saved.existed {
				t.Fatalf("rollback snapshot failed: %v", err)
			}
			if err := os.WriteFile(target, []byte("failed-update-candidate"), 0600); err != nil {
				t.Fatal(err)
			}
			if err := restoreSelfUpdateFiles([]selfUpdateFile{saved}); err != nil {
				t.Fatalf("rollback rejected: %v", err)
			}
			restored, err := os.ReadFile(target)
			if err != nil {
				t.Fatal(err)
			}
			if sha256.Sum256(restored) != sha256.Sum256(embedded) {
				t.Fatal("rollback failed to restore the original Windows executable")
			}
			t.Logf("EXTRACT_AND_ROLLBACK_PASS %s %x", name, sha256.Sum256(restored))
		})
	}
}

func TestGSC5PackagedSetupVersionAndMissingBackupFailClosed(t *testing.T) {
	versionReadme, err := payload.ReadFile("payload/README-v5.0.0-beta.1.txt")
	if err != nil || !bytes.Contains(versionReadme, []byte("5.0.0-beta.1")) {
		t.Fatalf("v5 beta payload documentation absent/mismatched: %v", err)
	}
	root := t.TempDir()
	target := filepath.Join(root, "GeumyiServerHost.exe")
	original := filepath.Join(root, "missing-original.exe")
	if err := os.WriteFile(target, []byte("candidate"), 0600); err != nil {
		t.Fatal(err)
	}
	err = restoreSelfUpdateFiles([]selfUpdateFile{{target: target, backup: original, existed: true}})
	if err == nil {
		t.Fatal("missing rollback source accepted")
	}
	data, e := os.ReadFile(target)
	if e != nil || string(data) != "candidate" {
		t.Fatal("failed restore unexpectedly modified candidate")
	}
}
