//go:build windows

package atomicfile

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// aclInfo captures the three security properties the ACL work reasons about.
// allowSIDs holds every Allow-ACE trustee resolved to its SID string, so tests
// compare by SID rather than by fragile SDDL short aliases (e.g. BUILTIN\Guests
// renders as "BG", never "S-1-5-32-546", in GetSecurityDescriptorSddlForm).
type aclInfo struct {
	sddl      string
	protected bool
	owner     string
	allowSIDs []string
}

func powershellOrSkip(t *testing.T) string {
	t.Helper()
	ps, err := exec.LookPath("powershell.exe")
	if err != nil {
		t.Skip("powershell.exe not available")
	}
	return ps
}

func getACL(t *testing.T, path string) aclInfo {
	t.Helper()
	ps := powershellOrSkip(t)
	// Emit one SID= line per Allow ACE (translated), plus SDDL/PROTECTED/OWNER.
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
		t.Fatalf("Get-Acl %s: %v", path, err)
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
		t.Fatalf("empty SDDL for %s: %q", path, out)
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

func runPS(t *testing.T, script string, args ...string) {
	t.Helper()
	ps := powershellOrSkip(t)
	full := "$ErrorActionPreference='Stop';" + script
	cmdArgs := append([]string{"-NoProfile", "-NonInteractive", "-Command", full}, args...)
	if out, err := exec.Command(ps, cmdArgs...).CombinedOutput(); err != nil {
		t.Fatalf("powershell setup failed: %v\n%s", err, out)
	}
}

// A distinctive inheritable ACE on the directory lets us prove the published
// file is a FRESH object that inherited the directory DACL, not a pre-planted
// file that kept its own protected DACL. BUILTIN\Guests is harmless and unusual.
const markerSID = "S-1-5-32-546"

func setDirMarker(t *testing.T, dir string) {
	runPS(t, `$d=$args[0];$a=Get-Acl -LiteralPath $d;`+
		`$ace=New-Object System.Security.AccessControl.FileSystemAccessRule(`+
		`(New-Object System.Security.Principal.SecurityIdentifier('`+markerSID+`')),`+
		`'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow');`+
		`$a.AddAccessRule($ace);Set-Acl -LiteralPath $d -AclObject $a`, dir)
}

func TestAtomicReplaceYieldsFreshInheritedDaclNotPreplanted(t *testing.T) {
	dir := t.TempDir()
	setDirMarker(t, dir)

	dst := filepath.Join(dir, "server.json")
	// Pre-plant the destination with a PROTECTED DACL (inheritance off) and the
	// marker ACE absent — models a file an attacker created first.
	runPS(t, `$p=$args[0];Set-Content -LiteralPath $p -Value 'PREPLANTED' -NoNewline;`+
		`$a=Get-Acl -LiteralPath $p;$a.SetAccessRuleProtection($true,$false);Set-Acl -LiteralPath $p -AclObject $a`, dst)

	before := getACL(t, dst)
	if !before.protected {
		t.Fatal("pre-plant should be protected (inheritance off)")
	}
	if before.hasAllow(markerSID) {
		t.Fatal("pre-plant unexpectedly already allows the marker SID")
	}

	if err := WriteFile(dst, []byte(`{"port":8787}`), 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	if b, _ := os.ReadFile(dst); string(b) != `{"port":8787}` {
		t.Fatalf("content not replaced: %q", b)
	}

	after := getACL(t, dst)
	if after.protected {
		t.Error("after replace: DACL still protected (stale pre-planted descriptor survived)")
	}
	if !after.hasAllow(markerSID) {
		t.Errorf("after replace: inherited marker ACE missing; allow=%v sddl=%s", after.allowSIDs, after.sddl)
	}
	if after.sddl == before.sddl {
		t.Error("after replace: DACL identical to pre-plant (file was reused, not replaced)")
	}
	t.Logf("before: protected=%v owner=%s allow=%v", before.protected, before.owner, before.allowSIDs)
	t.Logf("after : protected=%v owner=%s allow=%v", after.protected, after.owner, after.allowSIDs)
}

// When the destination does not exist yet, the new file must also inherit the
// directory DACL (no surprise protected descriptor).
func TestAtomicWriteFreshFileInheritsDirectoryDacl(t *testing.T) {
	dir := t.TempDir()
	setDirMarker(t, dir)
	dst := filepath.Join(dir, "trusted-devices.json")
	if err := WriteFile(dst, []byte("[]"), 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	after := getACL(t, dst)
	if after.protected {
		t.Error("fresh file unexpectedly has a protected DACL")
	}
	if !after.hasAllow(markerSID) {
		t.Errorf("fresh file did not inherit directory marker ACE; allow=%v sddl=%s", after.allowSIDs, after.sddl)
	}
}
