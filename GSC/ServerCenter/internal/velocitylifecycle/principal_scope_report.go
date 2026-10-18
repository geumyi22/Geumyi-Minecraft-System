package velocitylifecycle

import (
    "bytes"
    "encoding/json"
    "errors"
    "fmt"
    "time"
)

// PrincipalScopeReview classifies UNTRUSTED operator-provided account
// relationships only. No SID, token, username, key, executable path, task
// command or ACL is accepted in this schema. It is never OS attestation.
type PrincipalScopeReview struct {
    Schema int `json:"schema"`
    Result string `json:"result"`
    SourceVerified bool `json:"source_verified"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    CrossPrincipalSeparationObserved bool `json:"cross_principal_separation_observed"`
    DPAPICrossPrincipalCompatible bool `json:"dpapi_cross_principal_compatible"`
    GSCProcessPrincipalVerified bool `json:"gsc_process_principal_verified"`
    Findings []PrincipalScopeFinding `json:"findings"`
}

type PrincipalScopeFinding struct {
    Target string `json:"target"`
    TaskRunning bool `json:"task_running"`
    TaskAndJavaSameAccount bool `json:"task_and_java_same_account"`
    JavaParentAndChildSameAccount bool `json:"java_parent_and_child_same_account"`
    JavaVsCollector string `json:"java_vs_collector"`
    TaskVsCollector string `json:"task_vs_collector"`
    GSCProcessPrincipalVerified bool `json:"gsc_process_principal_verified"`
    DPAPICompatibilityVerified bool `json:"dpapi_compatibility_verified"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    Risk string `json:"risk"`
}

type principalScopeRaw struct {
    Schema int `json:"schema"`
    Kind string `json:"kind"`
    CollectedAtUTC string `json:"collected_at_utc"`
    Synthetic *bool `json:"synthetic"`
    ReadOnly *bool `json:"read_only"`
    ServerStateChanged *bool `json:"server_state_changed"`
    TaskStateModified *bool `json:"task_state_modified"`
    ACLModified *bool `json:"acl_modified"`
    AuditLogSettingsChanged *bool `json:"audit_log_settings_changed"`
    DPAPIAccessAttempted *bool `json:"dpapi_access_attempted"`
    PrivilegeElevationAttempted *bool `json:"privilege_elevation_attempted"`
    SourceAuthenticated *bool `json:"source_authenticated"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    CollectorAccountKind string `json:"collector_account_kind"`
    Result string `json:"result"`
    Instances []principalScopeRawEntry `json:"instances"`
}

type principalScopeRawEntry struct {
    ID string `json:"id"`
    TaskRunning *bool `json:"task_running"`
    TaskPrincipalResolved *bool `json:"task_principal_resolved"`
    UDPJavaOwnerResolved *bool `json:"udp_java_owner_resolved"`
    JavaParentAndChildSameOwner string `json:"java_parent_and_child_same_owner"`
    TaskPrincipalVsUDPJavaOwner string `json:"task_principal_vs_udp_java_owner"`
    TaskPrincipalVsCollector string `json:"task_principal_vs_collector"`
    UDPJavaOwnerVsCollector string `json:"udp_java_owner_vs_collector"`
    ReliableTaskToJVMIdentityVerified *bool `json:"reliable_task_to_jvm_identity_verified"`
    DPAPICrossProcessCompatibilityVerified *bool `json:"dpapi_cross_process_compatibility_verified"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    Result string `json:"result"`
}

func validRelationship(s string) bool {
    return s=="MATCH" || s=="DIFFERENT" || s=="UNKNOWN"
}

func consistentRelationships(a,b,c string) bool {
    // a: task vs Java; b: task vs collector; c: Java vs collector.
    // An asserted equality must agree with all other known equalities.
    if !validRelationship(a)||!validRelationship(b)||!validRelationship(c) {return false}
    if a=="MATCH" && b!="UNKNOWN" && c!="UNKNOWN" && b!=c {return false}
    if a=="DIFFERENT" && b=="MATCH" && c=="MATCH" {return false}
    if b=="MATCH" && c=="DIFFERENT" && a=="MATCH" {return false}
    if b=="DIFFERENT" && c=="MATCH" && a=="MATCH" {return false}
    return true
}

// ReviewPrincipalScopeReport rejects duplicates, unknown fields, inconsistent
// SID relationship assertions, forged provenance and all claimed authorizations.
// The response explicitly does NOT infer the GSC host account from the
// INTERACTIVE collector account. It cannot provision DPAPI secrets.
func ReviewPrincipalScopeReport(data []byte) (PrincipalScopeReview,error) {
    reject:=func(msg string)(PrincipalScopeReview,error){
        return PrincipalScopeReview{},errors.New(msg)
    }
    if len(data)==0 || len(data)>131072 {return reject("empty or oversized principal-scope report")}
    if err:=checkDistinctJSONKeys(data);err!=nil{return reject("ambiguous principal-scope JSON")}
    dec:=json.NewDecoder(bytes.NewReader(data))
    dec.DisallowUnknownFields()
    var raw principalScopeRaw
    if err:=dec.Decode(&raw);err!=nil{return reject("invalid principal-scope JSON schema")}
    if raw.Schema!=1 ||
        raw.Kind!="GEUMYI_GSC_452_VELOCITY_WINDOWS_PRINCIPAL_SCOPE_READ_ONLY" ||
        raw.Synthetic==nil||*raw.Synthetic ||
        raw.ReadOnly==nil||!*raw.ReadOnly ||
        raw.ServerStateChanged==nil||*raw.ServerStateChanged ||
        raw.TaskStateModified==nil||*raw.TaskStateModified ||
        raw.ACLModified==nil||*raw.ACLModified ||
        raw.AuditLogSettingsChanged==nil||*raw.AuditLogSettingsChanged ||
        raw.DPAPIAccessAttempted==nil||*raw.DPAPIAccessAttempted ||
        raw.PrivilegeElevationAttempted==nil||*raw.PrivilegeElevationAttempted ||
        raw.SourceAuthenticated==nil||*raw.SourceAuthenticated ||
        raw.LiveControlAuthorized==nil||*raw.LiveControlAuthorized ||
        len(raw.Instances)!=3 {
        return reject("principal-scope provenance or safety checks failed")
    }
    switch raw.CollectorAccountKind {
    case "UNKNOWN","USER_OR_OTHER","SERVICE","SYSTEM":
    default:return reject("invalid sanitized collector account kind")
    }
    if t,err:=time.Parse(time.RFC3339Nano,raw.CollectedAtUTC);err!=nil||t.IsZero(){
        return reject("invalid principal-scope timestamp")
    }
    entries:=make(map[string]principalScopeRawEntry,3)
    for _,e:=range raw.Instances{
        if !validTarget(e.ID){return reject("unknown principal-scope target")}
        if _,ok:=entries[e.ID];ok{return reject("duplicate principal-scope target")}
        entries[e.ID]=e
    }
    out:=PrincipalScopeReview{
        Schema:1,Result:"BLOCKED_DIFFERENT_OR_UNKNOWN_RUNTIME_PRINCIPALS",
        SourceVerified:false,LiveControlAuthorized:false,
        DPAPICrossPrincipalCompatible:false,GSCProcessPrincipalVerified:false,
        Findings:make([]PrincipalScopeFinding,0,3),
    }
    allResolved:=true
    for _,id:=range []string{"wild","playground","other"} {
        e,ok:=entries[id]
        if !ok || e.TaskRunning==nil||e.TaskPrincipalResolved==nil||
            e.UDPJavaOwnerResolved==nil||
            e.ReliableTaskToJVMIdentityVerified==nil||*e.ReliableTaskToJVMIdentityVerified||
            e.DPAPICrossProcessCompatibilityVerified==nil||*e.DPAPICrossProcessCompatibilityVerified||
            e.LiveControlAuthorized==nil||*e.LiveControlAuthorized {
            return reject(fmt.Sprintf("missing or forged flags for %s",id))
        }
        a,b,c,d:=e.TaskPrincipalVsUDPJavaOwner,e.TaskPrincipalVsCollector,
           e.UDPJavaOwnerVsCollector,e.JavaParentAndChildSameOwner
        if !consistentRelationships(a,b,c)||!validRelationship(d){
            return reject("contradictory account relationship")
        }
        if (!*e.TaskPrincipalResolved && (a!="UNKNOWN"||b!="UNKNOWN")) ||
            (!*e.UDPJavaOwnerResolved && (a!="UNKNOWN"||c!="UNKNOWN")) ||
            (a=="MATCH" && (!*e.TaskPrincipalResolved||!*e.UDPJavaOwnerResolved)) ||
            (d=="MATCH" && !*e.UDPJavaOwnerResolved) {
            return reject("resolved-account flags conflict with relationship")
        }
        complete:=*e.TaskRunning && *e.TaskPrincipalResolved &&
            *e.UDPJavaOwnerResolved && d!="UNKNOWN"
        wantResult:="PRINCIPAL_COMPARISON_INCOMPLETE_NO_GO"
        if complete {wantResult="PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED"} else {allResolved=false}
        if e.Result!=wantResult{return reject("contradictory per-instance classification")}
        if b=="DIFFERENT" || c=="DIFFERENT"{out.CrossPrincipalSeparationObserved=true}
        risk:="ACCOUNT_SCOPE_INCOMPLETE_NO_GO"
        if b=="DIFFERENT"||c=="DIFFERENT" {risk="INTERACTIVE_ACCOUNT_DIFFERS_NO_GO"
        }else if complete{risk="GSC_HOST_PRINCIPAL_NOT_PROVEN_NO_GO"}
        out.Findings=append(out.Findings,PrincipalScopeFinding{
            Target:id,TaskRunning:*e.TaskRunning,
            TaskAndJavaSameAccount:a=="MATCH",
            JavaParentAndChildSameAccount:d=="MATCH",
            JavaVsCollector:c,TaskVsCollector:b,
            GSCProcessPrincipalVerified:false,
            DPAPICompatibilityVerified:false,LiveControlAuthorized:false,
            Risk:risk,
        })
    }
    topResult:="PRINCIPAL_SCOPE_EVIDENCE_INCOMPLETE_NO_GO"
    if allResolved{topResult="THREE_PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED"}
    if raw.Result!=topResult{return reject("contradictory fleet classification")}
    return out,nil
}
