package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestProxyRollbackRestoresConfigAndJarBytes(t *testing.T) {
	root := t.TempDir()
	records := []externalProxyBackup{}
	for _, n := range []string{"plugin.jar", "config.yml"} {
		b := filepath.Join(root, n+".backup")
		l := filepath.Join(root, n)
		if e := os.WriteFile(b, []byte("original-"+n), 0600); e != nil {
			t.Fatal(e)
		}
		if e := os.WriteFile(l, []byte("migrated-"+n), 0600); e != nil {
			t.Fatal(e)
		}
		records = append(records, externalProxyBackup{l, b, true})
	}
	fresh := filepath.Join(root, "new-config.yml")
	if e := os.WriteFile(fresh, []byte("new"), 0600); e != nil {
		t.Fatal(e)
	}
	records = append(records, externalProxyBackup{Live: fresh})
	if e := restoreExternalProxyBackups(records); e != nil {
		t.Fatal(e)
	}
	for _, r := range records[:2] {
		a, _ := os.ReadFile(r.Live)
		b, _ := os.ReadFile(r.Backup)
		if string(a) != string(b) {
			t.Fatal("bytes not restored")
		}
	}
	if _, e := os.Stat(fresh); !os.IsNotExist(e) {
		t.Fatal("new config not removed")
	}
}
func TestProxyRollbackMissingBackupFailsClosed(t *testing.T) {
	root := t.TempDir()
	l := filepath.Join(root, "plugin.jar")
	if e := os.WriteFile(l, []byte("unchanged"), 0600); e != nil {
		t.Fatal(e)
	}
	if e := restoreExternalProxyBackups([]externalProxyBackup{{l, filepath.Join(root, "missing"), true}}); e == nil {
		t.Fatal("missing backup reported as success")
	}
	b, _ := os.ReadFile(l)
	if string(b) != "unchanged" {
		t.Fatal("source changed after missing backup")
	}
}
