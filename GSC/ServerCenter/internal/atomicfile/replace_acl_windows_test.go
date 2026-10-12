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
type aclInfo struct {
	sddl      string // DACL SDDL
	protected bool   // AreAccessRulesProtected (inheritance broken?)
	owner     string
}

func getACL(t *testing.T, path string) aclInfo {
	t.Helper()
	ps, err := exec.LookPath("powershell.exe")
	if err != nil {
		t.Skip("powershell.exe not available")
	}
	script := `$ErrorActionPreference='Stop';$a=Get-Acl -LiteralPath $args[0];` +
		`$sddl=$a.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access);` +
		`$o=$a.GetOwner([System.Security.Principal.SecurityIdentifier]).Value;` +
		`Write-Output ("SDDL=$sddl");Write-Output ("PROTECTED=$($a.AreAccessRulesProtected))");Write-Output ("OWNER=$o")`
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
		}
	}
	if info.sddl == "" {
		t.Fatalf("empty SDDL for %s: %q", path, out)
	}
	return info
}

func runPS(t *testing.T, script string, args ...string) {
	t.Helper()
	ps, err := exec.LookPath("powershell.exe")
	if err != nil {
		t.Skip("powershell.exe not available")
	}
	full := "$ErrorActionPreference='Stop';" + script
	cmdArgs := append([]string{"-NoProfile", "-NonInteractive", "-Command", full}, args...)
	if out, err := exec.Command(ps, cmdArgs...).CombinedOutput(); err != nil {
		t.Fatalf("powershell setup failed: %v\n%s", err, out)
	}
}

// A distinctive inherited ACE on the directory lets us prove the published file
// is a FRESH object that inherited the directory DACL, not a pre-planted file
// that kept its own protected DACL.
const markerSID = "S-1-5-32-546" // BUILTIN\Guests: harmless, unusual, easy to spot

func TestAtomicReplaceYieldsFreshInheritedDaclNotPreplanted(t *testing.T) {
	dir := t.TempDir()
	// Directory: inheritable marker ACE, inheritance enabled for children.
	runPS(t, `$d=$args[0];$a=Get-Acl -LiteralPath $d;`+
		`$ace=New-Object System.Security.AccessControl.FileSystemAccessRule(`+
		`(New-Object System.Security.Principal.SecurityIdentifier('`+markerSID+`')),`+
		`'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow');`+
		`$a.AddAccessRule($ace);Set-Acl -LiteralPath $d -AclObject $a`, dir)

	dst := filepath.Join(dir, "server.json")
	// Pre-plant the destination with a PROTECTED DACL (no inheritance) and the
	// marker ACE absent — this models a file an attacker created first.
	runPS(t, `$p=$args[0];Set-Content -LiteralPath $p -Value 'PREPLANTED' -NoNewline;`+
		`$a=Get-Acl -LiteralPath $p;$a.SetAccessRuleProtection($true,$false);Set-Acl -LiteralPath $p -AclObject $a`, dst)

	before := getACL(t, dst)
	if !before.protected {
		t.Fatal("pre-plant should be protected (inheritance off)")
	}
	if strings.Contains(before.sddl, markerSID) {
		t.Fatal("pre-plant unexpectedly already has the marker ACE")
	}

	if err := WriteFile(dst, []byte(`{"port":8787}`), 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	if b, _ := os.ReadFile(dst); string(b) != `{"port":8787}` {
		t.Fatalf("content not replaced: %q", b)
	}

	after := getACL(t, dst)
	// 1. The published file is a fresh object: inheritance is ON again.
	if after.protected {
		t.Error("after replace: DACL still protected (stale pre-planted descriptor survived)")
	}
	// 2. It inherited the directory's marker ACE (proves identity, not content, changed).
	if !strings.Contains(after.sddl, markerSID) {
		t.Errorf("after replace: inherited marker ACE missing; sddl=%s", after.sddl)
	}
	// 3. The security descriptor actually changed from the pre-plant.
	if after.sddl == before.sddl {
		t.Error("after replace: DACL identical to pre-plant (file was reused, not replaced)")
	}
	t.Logf("before: protected=%v owner=%s", before.protected, before.owner)
	t.Logf("after : protected=%v owner=%s sddl=%s", after.protected, after.owner, after.sddl)
}

// When the destination does not exist yet, the new file must also inherit the
// directory DACL (no surprise protected descriptor).
func TestAtomicWriteFreshFileInheritsDirectoryDacl(t *testing.T) {
	dir := t.TempDir()
	runPS(t, `$d=$args[0];$a=Get-Acl -LiteralPath $d;`+
		`$ace=New-Object System.Security.AccessControl.FileSystemAccessRule(`+
		`(New-Object System.Security.Principal.SecurityIdentifier('`+markerSID+`')),`+
		`'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow');`+
		`$a.AddAccessRule($ace);Set-Acl -LiteralPath $d -AclObject $a`, dir)
	dst := filepath.Join(dir, "trusted-devices.json")
	if err := WriteFile(dst, []byte("[]"), 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	after := getACL(t, dst)
	if after.protected {
		t.Error("fresh file unexpectedly has a protected DACL")
	}
	if !strings.Contains(after.sddl, markerSID) {
		t.Errorf("fresh file did not inherit directory marker ACE; sddl=%s", after.sddl)
	}
}
