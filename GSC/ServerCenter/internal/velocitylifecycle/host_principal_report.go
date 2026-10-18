package velocitylifecycle

import (
    "bytes"
    "encoding/json"
    "errors"
    "time"
)

// HostPrincipalReview reviews an UNTRUSTED sanitized read-only host-account
// observation. Same SID does not prove same executable, process generation,
// service authenticity, DPAPI key ownership, or permission to stop anything.
type HostPrincipalReview struct {
    Status string `json:"status"`
    SourceVerified bool `json:"source_verified"`
    ExecutableVerified bool `json:"executable_verified"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    HostProcessCountCategory string `json:"host_process_count_category"`
    HostVsCollector string `json:"host_vs_collector"`
    AllHostTaskSIDMatchHints bool `json:"all_host_task_sid_match_hints"`
    GSCServiceRuntimeAttested bool `json:"gsc_service_runtime_attested"`
    DPAPICompatible bool `json:"dpapi_compatible"`
    Findings []HostPrincipalFinding `json:"findings"`
}

type HostPrincipalFinding struct {
    Target string `json:"target"`
    TaskRunning bool `json:"task_running"`
    HostVsTaskPrincipal string `json:"host_vs_task_principal"`
    Verified bool `json:"verified"`
    DPAPICompatible bool `json:"dpapi_compatible"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
}

type hostPrincipalRaw struct {
    Schema int `json:"schema"`
    Kind string `json:"kind"`
    CollectedAtUTC string `json:"collected_at_utc"`
    Synthetic *bool `json:"synthetic"`
    ReadOnly *bool `json:"read_only"`
    ServerStateChanged *bool `json:"server_state_changed"`
    TaskStateModified *bool `json:"task_state_modified"`
    ACLModified *bool `json:"acl_modified"`
    DPAPIAccessAttempted *bool `json:"dpapi_access_attempted"`
    EventLogSettingsChanged *bool `json:"event_log_settings_changed"`
    PrivilegeElevationAttempted *bool `json:"privilege_elevation_attempted"`
    SourceAuthenticated *bool `json:"source_authenticated"`
    HostExecutableIdentityVerified *bool `json:"host_executable_identity_verified"`
    GSCServiceRuntimeAttested *bool `json:"gsc_service_runtime_attested"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    CollectorVsHost string `json:"collector_vs_host"`
    HostProcessCountCategory string `json:"gsc_host_process_count_category"`
    Result string `json:"result"`
    Instances []hostPrincipalRawEntry `json:"instances"`
}
type hostPrincipalRawEntry struct {
    ID string `json:"id"`
    TaskRunning *bool `json:"task_running"`
    TaskPrincipalResolved *bool `json:"task_principal_resolved"`
    HostVsTaskPrincipal string `json:"host_vs_task_principal"`
    TrustedProcessIdentityVerified *bool `json:"trusted_process_identity_verified"`
    DPAPICompatible *bool `json:"dpapi_compatible"`
    LiveControlAuthorized *bool `json:"live_control_authorized"`
    Result string `json:"result"`
}

// ReviewHostPrincipalReport rejects malformed or self-contradictory results.
// It classifies the supplied historical report only; it does not open a
// Windows process or connect to a real GSC service.
func ReviewHostPrincipalReport(data []byte) (HostPrincipalReview,error) {
    fail:=func()(HostPrincipalReview,error){
        return HostPrincipalReview{},errors.New("untrusted GSC host principal evidence rejected")
    }
    if len(data)==0||len(data)>131072{return fail()}
    if checkDistinctJSONKeys(data)!=nil{return fail()}
    dec:=json.NewDecoder(bytes.NewReader(data))
    dec.DisallowUnknownFields()
    var raw hostPrincipalRaw
    if dec.Decode(&raw)!=nil{return fail()}
    if raw.Schema!=1||raw.Kind!="GEUMYI_GSC_452_HOST_RUNTIME_PRINCIPAL_READ_ONLY"||
        raw.Synthetic==nil||*raw.Synthetic||
        raw.ReadOnly==nil||!*raw.ReadOnly||
        raw.ServerStateChanged==nil||*raw.ServerStateChanged||
        raw.TaskStateModified==nil||*raw.TaskStateModified||
        raw.ACLModified==nil||*raw.ACLModified||
        raw.DPAPIAccessAttempted==nil||*raw.DPAPIAccessAttempted||
        raw.EventLogSettingsChanged==nil||*raw.EventLogSettingsChanged||
        raw.PrivilegeElevationAttempted==nil||*raw.PrivilegeElevationAttempted||
        raw.SourceAuthenticated==nil||*raw.SourceAuthenticated||
        raw.HostExecutableIdentityVerified==nil||*raw.HostExecutableIdentityVerified||
        raw.GSCServiceRuntimeAttested==nil||*raw.GSCServiceRuntimeAttested||
        raw.LiveControlAuthorized==nil||*raw.LiveControlAuthorized||
        len(raw.Instances)!=3||!validRelationship(raw.CollectorVsHost){return fail()}
    if stamp,err:=time.Parse(time.RFC3339Nano,raw.CollectedAtUTC);err!=nil||stamp.IsZero(){return fail()}
    switch raw.HostProcessCountCategory{
    case "NONE","ONE","MULTIPLE","UNKNOWN":
    default: return fail()
    }
    if raw.HostProcessCountCategory!="ONE"&&raw.CollectorVsHost!="UNKNOWN"{return fail()}
    seen:=make(map[string]hostPrincipalRawEntry,3)
    for _,e:=range raw.Instances{
        if !validTarget(e.ID){return fail()}
        if _,ok:=seen[e.ID];ok{return fail()}
        seen[e.ID]=e
    }
    out:=HostPrincipalReview{
        Status:"HISTORICAL_HOST_ACCOUNT_HINTS_NO_GO",
        SourceVerified:false,ExecutableVerified:false,LiveControlAuthorized:false,
        HostProcessCountCategory:raw.HostProcessCountCategory,
        HostVsCollector:raw.CollectorVsHost,
        GSCServiceRuntimeAttested:false,DPAPICompatible:false,
        Findings:make([]HostPrincipalFinding,0,3),
    }
    allResolved:=raw.HostProcessCountCategory=="ONE"
    allMatch:=allResolved
    for _,id:=range []string{"wild","playground","other"}{
        e,ok:=seen[id]
        if !ok||e.TaskRunning==nil||e.TaskPrincipalResolved==nil||
            e.TrustedProcessIdentityVerified==nil||*e.TrustedProcessIdentityVerified||
            e.DPAPICompatible==nil||*e.DPAPICompatible||
            e.LiveControlAuthorized==nil||*e.LiveControlAuthorized||
            !validRelationship(e.HostVsTaskPrincipal){return fail()}
        if (!*e.TaskPrincipalResolved||raw.HostProcessCountCategory!="ONE") &&
            e.HostVsTaskPrincipal!="UNKNOWN"{return fail()}
        rowResult:="GSC_HOST_PRINCIPAL_UNVERIFIED_NO_GO"
        if e.HostVsTaskPrincipal!="UNKNOWN"{
            rowResult="GSC_HOST_TASK_ACCOUNT_RELATIONSHIP_ONLY_NO_GO"
        }
        if rowResult!=e.Result{return fail()}
        if !*e.TaskRunning||!*e.TaskPrincipalResolved||e.HostVsTaskPrincipal=="UNKNOWN"{
            allResolved=false
        }
        if e.HostVsTaskPrincipal!="MATCH"||!*e.TaskRunning||!*e.TaskPrincipalResolved{
            allMatch=false
        }
        out.Findings=append(out.Findings,HostPrincipalFinding{
            Target:id,TaskRunning:*e.TaskRunning,
            HostVsTaskPrincipal:e.HostVsTaskPrincipal,
            Verified:false,DPAPICompatible:false,LiveControlAuthorized:false,
        })
    }
    topResult:="GSC_HOST_PRINCIPAL_SCOPE_UNVERIFIED_NO_GO"
    if allResolved{topResult="GSC_HOST_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED"}
    if raw.Result!=topResult{return fail()}
    out.AllHostTaskSIDMatchHints=allMatch
    return out,nil
}
