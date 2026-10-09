//go:build windows

package main

import (
	"strings"
	"testing"
	"os"
	"path/filepath"
)

func TestGSCUpdateHealthRequiresExactTargetVersion(t *testing.T) {
	tests := []struct {
		name string
		body string
		version string
		want bool
	}{
		{"matching candidate", `{"ok":true,"version":"4.3.9-rc.2","service":true,"generation":4}`, "4.3.9-rc.2", true},
		{"not a service", `{"ok":true,"version":"4.3.9-rc.2","service":false,"generation":4}`, "4.3.9-rc.2", false},
		{"missing service flag", `{"ok":true,"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"old host must fail candidate", `{"ok":true,"version":"4.3.8","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"future host must fail candidate", `{"ok":true,"version":"4.3.9","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"stray http 200 invalid body", "OK", "4.3.9-rc.2", false},
		{"no ok", `{"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"not ok", `{"ok":false,"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"wrong generation", `{"ok":true,"version":"4.3.9-rc.2","generation":3}`, "4.3.9-rc.2", false},
		{"malformed json", `{"ok":true,"version":"4.3.9-rc.2"`, "4.3.9-rc.2", false},
		{"rollback gsc v4 accepted", `{"ok":true,"version":"4.3.8","service":true,"generation":4}`, "", true},
		{"rollback nonservice rejected", `{"ok":true,"version":"4.3.8","service":false,"generation":4}`, "", false},
		{"rollback empty version rejected", `{"ok":true,"version":"","generation":4}`, "", false},
		{"rollback unrelated service rejected", `{"ok":true,"version":"other","generation":2}`, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := gscHealthIsTarget(strings.NewReader(tt.body), tt.version)
			if got != tt.want {
				t.Fatalf("health version %q: got %v, want %v", tt.version, got, tt.want)
			}
		})
	}
}

func TestGSCBackupRestoreReturnsSuccessOnlyWhenFilesRestored(t *testing.T) {
	dir:=t.TempDir()
	target:=filepath.Join(dir,"GeumyiServerHost.exe")
	backup:=filepath.Join(dir,"previous-host.exe")
	newFile:=filepath.Join(dir,"new-client.exe")
	if err:=os.WriteFile(backup,[]byte("last-known-good"),0600);err!=nil{t.Fatal(err)}
	if err:=os.WriteFile(target,[]byte("new-but-bad"),0600);err!=nil{t.Fatal(err)}
	if err:=os.WriteFile(newFile,[]byte("new-only"),0600);err!=nil{t.Fatal(err)}
	files:=[]selfUpdateFile{
		{target:target,backup:backup,existed:true},
		{target:newFile,backup:filepath.Join(dir,"none"),existed:false},
	}
	if err:=restoreSelfUpdateFiles(files);err!=nil{t.Fatalf("safe restore failed: %v",err)}
	b,err:=os.ReadFile(target)
	if err!=nil||string(b)!="last-known-good"{t.Fatalf("original host not restored: %v",err)}
	if _,err:=os.Stat(newFile);!os.IsNotExist(err){t.Fatal("new-only file was not removed")}
}

func TestGSCRestoreNeverClaimsSuccessWhenBackupMissing(t *testing.T) {
	dir:=t.TempDir()
	missing:=filepath.Join(dir,"missing-old-client.exe")
	badTarget:=filepath.Join(dir,"GeumyiServerCenter.exe")
	goodTarget:=filepath.Join(dir,"GeumyiServerHost.exe")
	goodBackup:=filepath.Join(dir,"host-old-backup.exe")
	if err:=os.WriteFile(badTarget,[]byte("candidate"),0600);err!=nil{t.Fatal(err)}
	if err:=os.WriteFile(goodTarget,[]byte("candidate-host"),0600);err!=nil{t.Fatal(err)}
	if err:=os.WriteFile(goodBackup,[]byte("original-host"),0600);err!=nil{t.Fatal(err)}
	files:=[]selfUpdateFile{
		{target:badTarget,backup:missing,existed:true},
		{target:goodTarget,backup:goodBackup,existed:true},
	}
	if err:=restoreSelfUpdateFiles(files);err==nil{t.Fatal("missing old Client backup must fail closed")}
	hostData,err:=os.ReadFile(goodTarget)
	if err!=nil||string(hostData)!="original-host"{t.Fatal("remaining recoverable files must still be restored")}
	clientData,err:=os.ReadFile(badTarget)
	if err!=nil||string(clientData)!="candidate"{t.Fatal("missing backup must not invent a recovery")}
}


func TestGSCSelfUpdateLedgerAlwaysIncludesPotentialNewSetup(t *testing.T) {
	dir := t.TempDir()
	host := filepath.Join(dir, "GeumyiServerHost.exe")
	client := filepath.Join(dir, "GeumyiServerCenter.exe")
	setup := filepath.Join(dir, "GeumyiServerCenter-Setup.exe")
	cases := []struct {
		name string
		host bool
		client bool
		want []string
	}{
		{"host and client", true, true, []string{host, client, setup}},
		{"host only", true, false, []string{host, setup}},
		{"client only", false, true, []string{client, setup}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := selfUpdateTargetPaths(tc.host, tc.client, host, client, setup)
			if len(got) != len(tc.want) {
				t.Fatalf("got %d ledger paths, want %d", len(got), len(tc.want))
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("target[%d] = %q, want %q", i, got[i], tc.want[i])
				}
			}
		})
	}
}

func TestGSCFailedUpdateRemovesNewSetupAndRestoresHost(t *testing.T) {
	dir := t.TempDir()
	backupDir := filepath.Join(dir, "backup")
	if err := os.Mkdir(backupDir, 0700); err != nil {
		t.Fatal(err)
	}
	host := filepath.Join(dir, "GeumyiServerHost.exe")
	setup := filepath.Join(dir, "GeumyiServerCenter-Setup.exe")
	if err := os.WriteFile(host, []byte("original-host"), 0600); err != nil {
		t.Fatal(err)
	}
	// Setup did not exist before update (common on a pre-existing installation).
	paths := selfUpdateTargetPaths(true, false, host, "", setup)
	ledger := make([]selfUpdateFile, 0, len(paths))
	for _, path := range paths {
		record, err := backupSelfUpdateFile(path, backupDir)
		if err != nil {
			t.Fatal(err)
		}
		ledger = append(ledger, record)
	}
	if len(ledger) != 2 || !ledger[0].existed || ledger[1].existed {
		t.Fatalf("ledger must remember original Host and absent Setup: %+v", ledger)
	}
	if err := os.WriteFile(host, []byte("bad-candidate"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(setup, []byte("new-setup"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := restoreSelfUpdateFiles(ledger); err != nil {
		t.Fatalf("rollback failed: %v", err)
	}
	original, err := os.ReadFile(host)
	if err != nil || string(original) != "original-host" {
		t.Fatalf("rollback did not restore original Host: %v", err)
	}
	if _, err := os.Stat(setup); !os.IsNotExist(err) {
		t.Fatalf("new Setup binary was left behind after rollback: %v", err)
	}
}

func TestGSCFailedUpdateRestoresExistingSetup(t *testing.T) {
	dir := t.TempDir()
	backupDir := filepath.Join(dir, "backup")
	if err := os.Mkdir(backupDir, 0700); err != nil {
		t.Fatal(err)
	}
	setup := filepath.Join(dir, "GeumyiServerCenter-Setup.exe")
	if err := os.WriteFile(setup, []byte("original-setup"), 0600); err != nil {
		t.Fatal(err)
	}
	record, err := backupSelfUpdateFile(setup, backupDir)
	if err != nil || !record.existed {
		t.Fatalf("existing Setup backup failed: %v", err)
	}
	if err := os.WriteFile(setup, []byte("candidate-setup"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := restoreSelfUpdateFiles([]selfUpdateFile{record}); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(setup)
	if err != nil || string(content) != "original-setup" {
		t.Fatalf("existing Setup was not restored: %v", err)
	}
}
