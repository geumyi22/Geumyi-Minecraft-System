//go:build windows

package atomicfile

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// These Windows-only tests compare the DACL / Owner / inheritance of a file
// before and after atomicfile.WriteFile. They need powershell.exe and the
// ability to set ACLs on a disposable temp tree. When the runner cannot satisfy
// those preconditions the test reports UNVERIFIED via t.Skip (never a silent
// pass); only a real security-property violation is a failure.

type aclInfo struct {
	sddl      string
	protected bool
	owner     string
	allowSIDs []string // Allow-ACE trustees resolved to SID (SDDL aliases like "BG" avoided)
}

func powershellOrSkip(t *testing.T) string {
	t.Helper()
	// The Windows runner has PowerShell 7 available and runs its CI shell under
	// pwsh. Prefer that host for the ACL fixture rather than treating a broken
	// Windows PowerShell 5.1 module auto-import as a passing test skip.
	for _, executable := range []string{"pwsh.exe", "powershell.exe"} {
		if ps, err := exec.LookPath(executable); err == nil {
			return ps
		}
	}
	t.Skip("UNVERIFIED: neither pwsh.exe nor powershell.exe available")
	return ""
}

// setupPS runs an ACL/fixture setup command; a failure means the environment
// could not establish the precondition, so the test is UNVERIFIED (skipped).
func setupPS(t *testing.T, script string, args ...string) {
	t.Helper()
	ps := powershellOrSkip(t)
	full := "$ErrorActionPreference='Stop';" + script
	cmdArgs := append([]string{"-NoProfile", "-NonInteractive", "-Command", full}, args...)
	if out, err := exec.Command(ps, cmdArgs...).CombinedOutput(); err != nil {
		t.Skipf("UNVERIFIED: ACL fixture setup could not run: %v\n%s", err, out)
	}
}

func getACL(t *testing.T, path string) aclInfo {
	t.Helper()
	ps := powershellOrSkip(t)
	script := `$ErrorActionPreference='Stop';$a=Get-Acl -LiteralPath $args[0];` +
		`$sddl=$a.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access);` +
		`Write-Output ("SDDL=$sddl");` +
		`Write-Output ("PROTECTED=$($a.AreAccessRulesProtected)");` +
		`Write-Output ("OWNER=$($a.GetOwner([System.Security.Principal.SecurityIdentifier]).Value)");` +
		`foreach($r in $a.Access){ if($r.AccessControlType -eq 'Allow'){ ` +
		`try{$s=$r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value}catch{$s='UNRESOLVED'};` +
		`Write-Output ("SID=$s") } }`
	out, err := exec.Command(ps, "-NoProfile", "-NonInteractive", "-Command", script, path).Output()
	if err != nil {
		t.Skipf("UNVERIFIED: Get-Acl %s could not run: %v", path, err)
	}
	var info aclInfo
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "SDDL="):
			info.sddl = strings.TrimPrefix(line, "SDDL=")
		case strings.HasPrefix(line, "PROTECTED="):
			info.protected = strings.EqualFold(strings.TrimPrefix(line, "PROTECTED="), "True")
		case strings.HasPrefix(line, "OWNER="):
			info.owner = strings.TrimPrefix(line, "OWNER=")
		case strings.HasPrefix(line, "SID="):
			info.allowSIDs = append(info.allowSIDs, strings.TrimPrefix(line, "SID="))
		}
	}
	if info.sddl == "" {
		t.Skipf("UNVERIFIED: empty SDDL for %s: %q", path, out)
	}
	return info
}

func (a aclInfo) hasAllow(sid string) bool {
	for _, s := range a.allowSIDs {
		if strings.EqualFold(s, sid) {
			return true
		}
	}
	return false
}

// BUILTIN\Guests: harmless, unusual, easy to spot as an inherited marker.
const markerSID = "S-1-5-32-546"

func setDirMarker(t *testing.T, dir string) {
	setupPS(t, `$d=$args[0];$a=Get-Acl -LiteralPath $d;`+
		`$ace=New-Object System.Security.AccessControl.FileSystemAccessRule(`+
		`(New-Object System.Security.Principal.SecurityIdentifier('`+markerSID+`')),`+
		`'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow');`+
		`$a.AddAccessRule($ace);Set-Acl -LiteralPath $d -AclObject $a`, dir)
}

func TestAtomicReplaceYieldsFreshInheritedDaclNotPreplanted(t *testing.T) {
	dir := t.TempDir()
	setDirMarker(t, dir)

	dst := filepath.Join(dir, "server.json")
	// Pre-plant a PROTECTED destination with the marker ACE absent (an
	// attacker-created-first model). SetAccessRuleProtection($true,$true) COPIES
	// the current inherited ACEs as explicit, so SYSTEM/Administrators keep full
	// control (the file stays deletable/replaceable) while inheritance is off;
	// then the marker ACE is purged.
	setupPS(t, `$p=$args[0];Set-Content -LiteralPath $p -Value 'PREPLANTED' -NoNewline;`+
		`$a=Get-Acl -LiteralPath $p;$a.SetAccessRuleProtection($true,$true);`+
		`$a.PurgeAccessRules((New-Object System.Security.Principal.SecurityIdentifier('`+markerSID+`')));`+
		`Set-Acl -LiteralPath $p -AclObject $a`, dst)

	before := getACL(t, dst)
	if !before.protected {
		t.Skip("UNVERIFIED: pre-plant did not become protected on this runner")
	}
	if before.hasAllow(markerSID) {
		t.Skip("UNVERIFIED: pre-plant still allows the marker SID")
	}

	if err := WriteFile(dst, []byte(`{"port":8787}`), 0600); err != nil {
		t.Fatalf("WriteFile replace failed: %v", err)
	}
	if b, _ := os.ReadFile(dst); string(b) != `{"port":8787}` {
		t.Fatalf("content not replaced: %q", b)
	}

	after := getACL(t, dst)
	// Security properties — real failures if violated:
	if after.protected {
		t.Error("after replace: DACL still protected (stale pre-planted descriptor survived)")
	}
	if !after.hasAllow(markerSID) {
		t.Errorf("after replace: inherited marker ACE missing; allow=%v sddl=%s", after.allowSIDs, after.sddl)
	}
	if after.sddl == before.sddl {
		t.Error("after replace: DACL identical to pre-plant (file reused, not replaced)")
	}
	t.Logf("before: protected=%v owner=%s allow=%v", before.protected, before.owner, before.allowSIDs)
	t.Logf("after : protected=%v owner=%s allow=%v", after.protected, after.owner, after.allowSIDs)
}

func TestAtomicWriteFreshFileInheritsDirectoryDacl(t *testing.T) {
	dir := t.TempDir()
	setDirMarker(t, dir)
	dst := filepath.Join(dir, "trusted-devices.json")
	if err := WriteFile(dst, []byte("[]"), 0600); err != nil {
		t.Fatalf("WriteFile failed: %v", err)
	}
	after := getACL(t, dst)
	if after.protected {
		t.Error("fresh file unexpectedly has a protected DACL")
	}
	if !after.hasAllow(markerSID) {
		t.Errorf("fresh file did not inherit directory marker ACE; allow=%v sddl=%s", after.allowSIDs, after.sddl)
	}
}
