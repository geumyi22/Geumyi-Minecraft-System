package velocitylifecycle

import (
	"encoding/xml"
	"errors"
	"regexp"
	"strconv"
	"strings"
)

// SchedulerAssessment inspects ONLY supplied XML bytes in memory. It never
// reads Windows Task Scheduler, launches a JVM or provides execution approval.
// Names/paths/commands are deliberately not returned to callers.
type SchedulerAssessment struct {
	Schema int `json:"schema"`
	ReadOnly bool `json:"read_only"`
	Target string `json:"target"`
	SingleExecExpected bool `json:"single_exec_expected"`
	SYSTEMPrincipal bool `json:"system_principal"`
	AutoRestartEnabled bool `json:"auto_restart_enabled"`
	RestartCount int `json:"restart_count"`
	RestartPolicyUnverified bool `json:"restart_policy_unverified"`
	SafeToStart bool `json:"safe_to_start"`
	SafeToStop bool `json:"safe_to_stop"`
	SafeToRestart bool `json:"safe_to_restart"`
	Reasons []string `json:"reasons"`
}

const schedulerTaskNamespace = "http://schemas.microsoft.com/windows/2004/02/mit/task"

type schedulerXML struct {
	XMLName xml.Name `xml:"Task"`
	Actions struct {
		Items []struct {
			XMLName xml.Name
			Command string `xml:"Command"`
			Arguments string `xml:"Arguments"`
			WorkingDirectory string `xml:"WorkingDirectory"`
		} `xml:",any"`
	} `xml:"Actions"`
	Principals struct {
		Items []struct{
			UserID string `xml:"UserId"`
			LogonType string `xml:"LogonType"`
		} `xml:"Principal"`
	} `xml:"Principals"`
	Settings struct {
		RestartOnFailure struct {
			Count string `xml:"Count"`
			Interval string `xml:"Interval"`
		} `xml:"RestartOnFailure"`
		MultipleInstancesPolicy string `xml:"MultipleInstancesPolicy"`
	} `xml:"Settings"`
}

var velocityJarArgument = regexp.MustCompile(`(?i)(?:^|\s)-jar\s+(?:"velocity\.jar"|velocity\.jar)(?:\s|$)`)

// InspectSchedulerXML is a structural policy check, not a source of task-to-PID
// identity or proof that scheduled automatic restart is disabled for stop.
func InspectSchedulerXML(target string, contents []byte) (SchedulerAssessment, error) {
	if !validTarget(target) || len(contents) == 0 || len(contents) > 65536 {
		return SchedulerAssessment{}, errors.New("unknown target or invalid scheduler XML size")
	}
	var task schedulerXML
	if err := xml.Unmarshal(contents, &task); err != nil ||
		task.XMLName.Local != "Task" || task.XMLName.Space != schedulerTaskNamespace {
		return SchedulerAssessment{}, errors.New("invalid Windows scheduled task definition")
	}
	out := SchedulerAssessment{
		Schema:1, ReadOnly:true, Target:target,
		SafeToStart:false, SafeToStop:false, SafeToRestart:false,
		Reasons:[]string{"task_to_jvm_process_identity_unverified","operator_authorization_unavailable","graceful_bridge_unavailable"},
	}
	if len(task.Actions.Items) == 1 {
		action := task.Actions.Items[0]
		dir := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(action.WorkingDirectory), "/", "\\"))
		command := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(action.Command), "/", "\\"))
		out.SingleExecExpected = action.XMLName.Local == "Exec" &&
			strings.HasSuffix(command, "\\java.exe") &&
			strings.HasSuffix(dir, "\\"+target) &&
			velocityJarArgument.MatchString(action.Arguments)
	}
	if !out.SingleExecExpected {
		out.Reasons = append(out.Reasons,"task_definition_action_not_trusted")
	}
	if len(task.Principals.Items) == 1 {
		principal:=task.Principals.Items[0]
		out.SYSTEMPrincipal = strings.EqualFold(strings.TrimSpace(principal.UserID),"S-1-5-18") &&
			strings.EqualFold(strings.TrimSpace(principal.LogonType),"ServiceAccount")
	}
	if !out.SYSTEMPrincipal { out.Reasons = append(out.Reasons, "task_principal_unverified") }
	countText := strings.TrimSpace(task.Settings.RestartOnFailure.Count)
	if countText == "" {
		out.RestartPolicyUnverified=true
		out.Reasons=append(out.Reasons, "restart_policy_absent_or_unknown")
	} else {
		count,err:=strconv.Atoi(countText)
		if err!=nil || count<0 || count>99999 {
			out.RestartPolicyUnverified=true
			out.Reasons=append(out.Reasons,"restart_count_invalid")
		} else {
			out.RestartCount=count
			out.AutoRestartEnabled=count>0
			if out.AutoRestartEnabled {
				out.Reasons=append(out.Reasons,"auto_restart_can_respawn_shutdown_proxy")
			}
		}
	}
	// A scheduled task XML is merely a definition, not an authenticated
	// runtime identity. All actual lifecycle permissions stay false.
	return out,nil
}
