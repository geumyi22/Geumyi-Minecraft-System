package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRapidBackupSnapshotsRemainIndependentlyRestorable(t *testing.T) {
	s, cleanup := setupBackupPolicyTest(t)
	defer cleanup()
	seen := map[string]string{}
	var latest string
	for _, contents := range []string{"first", "second", "third"} {
		if err := os.WriteFile(filepath.Join(s.Path, "server.properties"), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
		snapshot, err := createBackup(s, "config", false)
		if err != nil {
			t.Fatal(err)
		}
		if _, exists := seen[snapshot.File]; exists {
			t.Fatalf("new backup replaced %s", snapshot.File)
		}
		seen[snapshot.File] = contents
		latest = snapshot.File
	}
	plan := buildBackupRetentionDryRun(s, 1)
	if len(plan.Kept) != 1 || plan.Kept[0].File != latest {
		t.Fatalf("retention must keep newest backup %s, got %+v", latest, plan.Kept)
	}
	for name, contents := range seen {
		path, err := safeBackupPath(s, name)
		if err != nil {
			t.Fatal(err)
		}
		manifest, err := readBackupManifest(path)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := verifyBackup(path); err != nil {
			t.Fatal(err)
		}
		restored := t.TempDir()
		if err := extractBackup(path, restored, manifest); err != nil {
			t.Fatal(err)
		}
		got, err := os.ReadFile(filepath.Join(restored, "server.properties"))
		if err != nil || string(got) != contents {
			t.Fatalf("restore %s: got %q, want %q, error %v", name, got, contents, err)
		}
	}
}

func TestUnreadableBackupProtectionBlocksTrash(t *testing.T) {
	s, cleanup := setupBackupPolicyTest(t)
	defer cleanup()
	snapshot, err := createBackup(s, "config", false)
	if err != nil {
		t.Fatal(err)
	}
	path, err := safeBackupPath(s, snapshot.File)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(backupMetaPath(path), []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path+".sha256", nil, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := verifyBackup(path); err == nil {
		t.Fatal("accepted empty checksum sidecar")
	}
	if _, err := trashBackupFile(s, snapshot.File); err == nil {
		t.Fatal("moved a backup with unreadable protection metadata")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
}

func TestMoveBackupBundlePreservesExistingSidecars(t *testing.T) {
	for _, suffix := range []string{".sha256", ".gscmeta.json"} {
		t.Run(suffix, func(t *testing.T) {
			root := t.TempDir()
			src, dst := filepath.Join(root, "saved.zip"), filepath.Join(root, "trash", "saved.zip")
			if err := os.MkdirAll(filepath.Dir(dst), 0700); err != nil {
				t.Fatal(err)
			}
			for p, body := range map[string]string{src: "archive", src + ".sha256": "checksum", dst + suffix: "existing sidecar"} {
				if err := os.WriteFile(p, []byte(body), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err := moveBackupBundle(src, dst); err == nil {
				t.Errorf("move succeeded with conflicting %s sidecar", suffix)
			}
			for p, want := range map[string]string{src: "archive", src + ".sha256": "checksum", dst + suffix: "existing sidecar"} {
				got, err := os.ReadFile(p)
				if err != nil || string(got) != want {
					t.Errorf("%s: expected %q, got %q (%v)", p, want, got, err)
				}
			}
		})
	}
}
