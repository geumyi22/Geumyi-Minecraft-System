package velocitylifecycle

import (
    "bytes"
    "encoding/json"
    "errors"
    "fmt"
    "strings"
    "time"
)

// TaskInstanceReview inspects caller-supplied, SANITIZED read-only Task Scheduler
// COM EnginePID hints. It does not read the OS, attest a task engine, or grant
// process control. EnginePID is not necessarily the action's Java process PID.
type TaskInstanceReview struct {
    Schema int `json:"schema"`
    ReadOnly bool `json:"read_only"`
    Result string `json:"result"`
    SourceVerified bool `json:"source_verified"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    Findings []TaskInstanceFinding `json:"findings"`
}

type TaskInstanceFinding struct {
    Target string `json:"target"`
    TaskRunning bool `json:"task_running"`
    VisibleInstanceCount int `json:"visible_instance_count"`
    InstanceQueryStatus string `json:"instance_query_status"`
    EngineParentHint bool `json:"engine_parent_hint"`
    UDPJavaPairHint bool `json:"udp_java_pair_hint"`
    Risk string `json:"risk"`
    ReliableTaskToJVMIdentityVerified bool `json:"reliable_task_to_jvm_identity_verified"`
    SafeToStart bool `json:"safe_to_start"`
    SafeToStop bool `json:"safe_to_stop"`
    SafeToRestart bool `json:"safe_to_restart"`
}

type taskInstanceRaw struct {
    Schema int `json:"schema"`
    Kind string `json:"kind"`
    CollectedAtUTC string `json:"collected_at_utc"`
    Synthetic *bool `json:"synthetic"`
    ServerStateChanged *bool `json:"server_state_changed"`
    TaskStateModified *bool `json:"task_state_modified"`
    AuditLogSettingsChanged *bool `json:"audit_log_settings_changed"`
    PrivilegeElevationAttempted *bool `json:"privilege_elevation_attempted"`
    ReadOnly *bool `json:"read_only"`
    TaskInstanceSource string `json:"task_instance_source"`
    SourceAuthenticated *bool `json:"source_authenticated"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    Result string `json:"result"`
    Instances []taskInstanceRawEntry `json:"instances"`
}

type taskInstanceRawEntry struct {
    ID string `json:"id"`
    TaskRunning *bool `json:"task_running"`
    InstanceQueryStatus string `json:"instance_query_status"`
    VisibleInstanceCount *int `json:"visible_instance_count"`
    EnginePIDPresent *bool `json:"engine_pid_present"`
    EnginePIDVisibleAsProcess *bool `json:"engine_pid_visible_as_process"`
    EnginePIDMatchesJavaParent *bool `json:"engine_pid_matches_java_parent"`
    EnginePIDMatchesUDPJavaChild *bool `json:"engine_pid_matches_udp_java_child"`
    UDPJavaPairHint *bool `json:"udp_java_pair_hint"`
    InstanceToJVMSuggestive *bool `json:"instance_to_jvm_suggestive"`
    ReliableTaskToJVMIdentityVerified *bool `json:"reliable_task_to_jvm_identity_verified"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    SafeToStart *bool `json:"safe_to_start"`
    SafeToStop *bool `json:"safe_to_stop"`
    SafeToRestart *bool `json:"safe_to_restart"`
    Result string `json:"result"`
}

// ReviewTaskInstanceReport validates an in-memory report against the exact
// collector contract. The file content is untrusted user input even when its
// booleans are self-consistent. No successful return is live authorization.
func ReviewTaskInstanceReport(data []byte) (TaskInstanceReview, error) {
    reject := func(reason string) (TaskInstanceReview,error) {
        return TaskInstanceReview{},errors.New(reason)
    }
    if len(data)==0 || len(data)>131072 {
        return reject("empty or oversized task instance evidence")
    }
    if err:=checkDistinctJSONKeys(data);err!=nil {
        return reject("ambiguous or invalid task instance JSON")
    }
    decoder:=json.NewDecoder(bytes.NewReader(data))
    decoder.DisallowUnknownFields()
    var raw taskInstanceRaw
    if err:=decoder.Decode(&raw);err!=nil {
        return reject("invalid task instance schema")
    }
    if raw.Schema!=1 ||
        raw.Kind!="GEUMYI_GSC_452_VELOCITY_TASK_INSTANCE_COM_READ_ONLY" ||
        raw.TaskInstanceSource!="WINDOWS_TASKSCHD_COM_READ_ONLY" ||
        raw.Result!="TASK_INSTANCE_HINTS_UNVERIFIED_NO_GO" ||
        raw.Synthetic==nil || *raw.Synthetic ||
        raw.ServerStateChanged==nil || *raw.ServerStateChanged ||
        raw.TaskStateModified==nil || *raw.TaskStateModified ||
        raw.AuditLogSettingsChanged==nil || *raw.AuditLogSettingsChanged ||
        raw.PrivilegeElevationAttempted==nil || *raw.PrivilegeElevationAttempted ||
        raw.ReadOnly==nil || !*raw.ReadOnly ||
        raw.SourceAuthenticated==nil || *raw.SourceAuthenticated ||
        raw.LiveControlAuthorized==nil || *raw.LiveControlAuthorized ||
        len(raw.Instances)!=3 {
        return reject("report provenance or safety flags failed")
    }
    date,err:=time.Parse(time.RFC3339Nano,raw.CollectedAtUTC)
    if err!=nil || date.IsZero() {
        return reject("invalid report timestamp")
    }
    byTarget:=make(map[string]taskInstanceRawEntry,3)
    for _,entry:=range raw.Instances {
        if !validTarget(entry.ID) { return reject("unknown Velocity target") }
        if _,ok:=byTarget[entry.ID];ok { return reject("duplicate Velocity target") }
        byTarget[entry.ID]=entry
    }
    out:=TaskInstanceReview{
        Schema:1, ReadOnly:true, Result:"BLOCKED_LIVE_CONTROL",
        SourceVerified:false, LiveControlAuthorized:false,
        Findings:make([]TaskInstanceFinding,0,3),
    }
    for _,id:=range []string{"wild","playground","other"} {
        e,ok:=byTarget[id]
        if !ok ||
            e.TaskRunning==nil || e.VisibleInstanceCount==nil ||
            e.EnginePIDPresent==nil || e.EnginePIDVisibleAsProcess==nil ||
            e.EnginePIDMatchesJavaParent==nil || e.EnginePIDMatchesUDPJavaChild==nil ||
            e.UDPJavaPairHint==nil || e.InstanceToJVMSuggestive==nil ||
            e.ReliableTaskToJVMIdentityVerified==nil || *e.ReliableTaskToJVMIdentityVerified ||
            e.LiveControlAuthorized==nil || *e.LiveControlAuthorized ||
            e.SafeToStart==nil || *e.SafeToStart ||
            e.SafeToStop==nil || *e.SafeToStop ||
            e.SafeToRestart==nil || *e.SafeToRestart {
            return reject(fmt.Sprintf("missing or forged safety fields for %s",id))
        }
        count:=*e.VisibleInstanceCount
        if count<0 || count>2 { return reject("unbounded visible instances") }
        switch e.InstanceQueryStatus {
        case "ONE_VISIBLE":
            if count!=1 { return reject("inconsistent single-instance status") }
        case "MULTIPLE_VISIBLE":
            if count!=2 { return reject("inconsistent multi-instance status") }
        case "NO_VISIBLE_INSTANCE","COM_UNAVAILABLE","COM_QUERY_FAILED_OR_ACCESS_DENIED":
            if count!=0 { return reject("visible count conflicts with query status") }
        default:
            return reject("unknown COM query status")
        }
        hasEngine:=*e.EnginePIDPresent
        visibleEngine:=*e.EnginePIDVisibleAsProcess
        parentMatch:=*e.EnginePIDMatchesJavaParent
        childMatch:=*e.EnginePIDMatchesUDPJavaChild
        pair:=*e.UDPJavaPairHint
        suggest:=*e.InstanceToJVMSuggestive
        if (hasEngine && e.InstanceQueryStatus!="ONE_VISIBLE") ||
            (visibleEngine && !hasEngine) ||
            ((parentMatch||childMatch) && (!visibleEngine || !pair)) ||
            (parentMatch && childMatch) ||
            suggest!=(parentMatch||childMatch) {
            return reject("contradictory process/COM hints")
        }
        risk:="TASK_INSTANCE_OR_JAVA_CORRELATION_UNVERIFIED"
        result:=risk
        if !*e.TaskRunning { result="TASK_STATE_NOT_CONFIRMED_NO_GO"; risk=result
        }else if suggest { result="ENGINE_PID_PAIR_HINT_NOT_AUTHENTICATED";risk="ENGINE_PID_HINT_ONLY_NO_GO"
        }else if e.InstanceQueryStatus=="NO_VISIBLE_INSTANCE" {
            result="INSTANCE_NOT_VISIBLE_CONTEXT_UNVERIFIED";risk="INSTANCE_VISIBILITY_NO_GO"
        }
        if strings.TrimSpace(e.Result)!=result {
            return reject("contradictory per-target classification")
        }
        out.Findings=append(out.Findings,TaskInstanceFinding{
            Target:id, TaskRunning:*e.TaskRunning,
            VisibleInstanceCount:count, InstanceQueryStatus:e.InstanceQueryStatus,
            EngineParentHint:parentMatch, UDPJavaPairHint:pair,
            Risk:risk, ReliableTaskToJVMIdentityVerified:false,
            SafeToStart:false, SafeToStop:false, SafeToRestart:false,
        })
    }
    return out,nil
}
