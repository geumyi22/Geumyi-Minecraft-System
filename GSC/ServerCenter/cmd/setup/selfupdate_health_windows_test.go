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
		{"old host must fail candidate", `{"ok":true,"version":"4.3.8","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"future host must fail candidate", `{"ok":true,"version":"4.3.9","service":true,"generation":4}`, "4.3.9-rc.2", false},
		{"stray http 200 invalid body", "OK", "4.3.9-rc.2", false},
		{"no ok", `{"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"not ok", `{"ok":false,"version":"4.3.9-rc.2","generation":4}`, "4.3.9-rc.2", false},
		{"wrong generation", `{"ok":true,"version":"4.3.9-rc.2","generation":3}`, "4.3.9-rc.2", false},
		{"malformed json", `{"ok":true,"version":"4.3.9-rc.2"`, "4.3.9-rc.2", false},
		{"rollback gsc v4 accepted", `{"ok":true,"version":"4.3.8","generation":4}`, "", true},
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
