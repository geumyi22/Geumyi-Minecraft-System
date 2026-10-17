package velocitylifecycle

import (
	"fmt"
	"strings"
	"testing"
)

func schedulerFixture(id string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task" version="1.6">
  <Principals><Principal id="Author">
    <UserId>S-1-5-18</UserId><LogonType>ServiceAccount</LogonType>
  </Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure><Interval>PT1M</Interval><Count>999</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author"><Exec>
    <Command>C:\Program Files\Java\java.exe</Command>
    <Arguments>-Xmx3G -jar "velocity.jar" nogui</Arguments>
    <WorkingDirectory>C:\ProgramData\GeumyiServerCenter\Network\FourServer\%s</WorkingDirectory>
  </Exec></Actions>
</Task>`, id)
}

func TestDay10SchedulerRestartHazardIsDetectedWithoutLiveApproval(t *testing.T) {
	for _, id:=range []string{"wild","playground","other"} {
		t.Run(id,func(t *testing.T){
			a,err:=InspectSchedulerXML(id,[]byte(schedulerFixture(id)))
			if err!=nil { t.Fatal(err) }
			if !a.ReadOnly || a.Schema!=1 || a.Target!=id ||
				!a.SYSTEMPrincipal || !a.SingleExecExpected ||
				!a.AutoRestartEnabled || a.RestartCount!=999 ||
				a.RestartPolicyUnverified || a.SafeToStart || a.SafeToStop || a.SafeToRestart {
				t.Fatalf("auto-restarting SYSTEM task incorrectly marked as safe: %+v",a)
			}
			if !strings.Contains(strings.Join(a.Reasons,","),"auto_restart_can_respawn_shutdown_proxy") {
				t.Fatal("risk missing from task assessment")
			}
		})
	}
}

func TestSchedulerMutationDoesNotPermitLifecycle(t *testing.T) {
	for _,tc:=range []struct{
		name string
		change func(string)string
		wanted string
	}{
		{"powershell_action",func(s string)string{return strings.Replace(s,"java.exe","powershell.exe",1)},"action"},
		{"wrong_jar",func(s string)string{return strings.Replace(s,"velocity.jar","unrelated.jar",1)},"action"},
		{"wrong_directory",func(s string)string{return strings.Replace(s,"FourServer\\wild","FourServer\\other",1)},"action"},
		{"extra_shell_action",func(s string)string{return strings.Replace(s,"</Exec></Actions>","</Exec><ComHandler><ClassId>{0000}</ClassId></ComHandler></Actions>",1)},"action"},
		{"wrong_identity",func(s string)string{return strings.Replace(s,"S-1-5-18","S-1-5-21-1234",1)},"principal"},
		{"missing_restart_count",func(s string)string{return strings.Replace(s,"<Count>999</Count>","",1)},"unknown"},
		{"invalid_restart_count",func(s string)string{return strings.Replace(s,"<Count>999</Count>","<Count>abc</Count>",1)},"unknown"},
		{"restart_count_zero",func(s string)string{return strings.Replace(s,"<Count>999</Count>","<Count>0</Count>",1)},"zero"},
	} {
		t.Run(tc.name,func(t *testing.T){
			a,err:=InspectSchedulerXML("wild",[]byte(tc.change(schedulerFixture("wild"))))
			if err!=nil{t.Fatal(err)}
			if !a.ReadOnly || a.SafeToStart || a.SafeToStop || a.SafeToRestart {
				t.Fatalf("mutation unlocked live task controls: %+v",a)
			}
			switch tc.wanted {
			case "action":
				if a.SingleExecExpected {t.Fatalf("untrusted action accepted: %+v",a)}
			case "principal":
				if a.SYSTEMPrincipal {t.Fatalf("wrong principal accepted: %+v",a)}
			case "unknown":
				if !a.RestartPolicyUnverified {t.Fatalf("unknown scheduler restart risk accepted: %+v",a)}
			case "zero":
				if a.AutoRestartEnabled || a.RestartPolicyUnverified || a.RestartCount!=0 {
					t.Fatalf("explicit zero-count policy misparsed: %+v",a)
				}
			}
		})
	}
}

func TestSchedulerAssessmentStrictInputScope(t *testing.T) {
	valid:=schedulerFixture("wild")
	for _,tc:=range []struct{target,contents string}{
		{"all",valid},
		{"wild",""},
		{"wild",strings.Repeat("A",65537)},
		{"wild",strings.Replace(valid,"http://schemas.microsoft.com/windows/2004/02/mit/task","http://example.org/fake",1)},
		{"wild","<Task><Actions></Task>"},
	} {
		if _,err:=InspectSchedulerXML(tc.target,[]byte(tc.contents));err==nil{
			t.Fatalf("accepted invalid input: target=%q length=%d",tc.target,len(tc.contents))
		}
	}
}
