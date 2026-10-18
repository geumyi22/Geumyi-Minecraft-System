package velocitylifecycle

import (
    "encoding/json"
    "strings"
    "testing"
)

func principalFixture() map[string]any {
    instances:=make([]any,0,3)
    for _,id:=range []string{"wild","playground","other"} {
        instances=append(instances,map[string]any{
            "id":id,"task_running":true,"task_principal_resolved":true,
            "udp_java_owner_resolved":true,
            "java_parent_and_child_same_owner":"MATCH",
            "task_principal_vs_udp_java_owner":"MATCH",
            "task_principal_vs_collector":"DIFFERENT",
            "udp_java_owner_vs_collector":"DIFFERENT",
            "reliable_task_to_jvm_identity_verified":false,
            "dpapi_cross_process_compatibility_verified":false,
            "live_control_authorized":false,
            "result":"PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED",
        })
    }
    return map[string]any{
        "schema":1,
        "kind":"GEUMYI_GSC_452_VELOCITY_WINDOWS_PRINCIPAL_SCOPE_READ_ONLY",
        "collected_at_utc":"2026-10-18T17:09:32.5056097+00:00",
        "synthetic":false,"read_only":true,
        "server_state_changed":false,"task_state_modified":false,
        "acl_modified":false,"audit_log_settings_changed":false,
        "dpapi_access_attempted":false,"privilege_elevation_attempted":false,
        "source_authenticated":false,"live_control_authorized":false,
        "collector_account_kind":"USER_OR_OTHER",
        "result":"THREE_PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED",
        "instances":instances,
    }
}
func asPrincipalJSON(m map[string]any) []byte {
    data,err:=json.Marshal(m)
    if err!=nil{panic(err)}
    return data
}
func principalRows(m map[string]any) []any {
    return m["instances"].([]any)
}
func principalRow(m map[string]any,i int) map[string]any {
    return principalRows(m)[i].(map[string]any)
}

func TestRealShapePrincipalReportSeparatesCollectorFromJavaTasks(t *testing.T){
    report,err:=ReviewPrincipalScopeReport(asPrincipalJSON(principalFixture()))
    if err!=nil{t.Fatal(err)}
    if len(report.Findings)!=3||report.SourceVerified||report.LiveControlAuthorized||
        !report.CrossPrincipalSeparationObserved||report.GSCProcessPrincipalVerified||
        report.DPAPICrossPrincipalCompatible||report.Result!="BLOCKED_DIFFERENT_OR_UNKNOWN_RUNTIME_PRINCIPALS" {
        t.Fatalf("untrusted report was promoted to cross-principal authority: %+v",report)
    }
    for i,id:=range []string{"wild","playground","other"}{
        f:=report.Findings[i]
        if f.Target!=id||!f.TaskRunning||!f.TaskAndJavaSameAccount||
            !f.JavaParentAndChildSameAccount||f.JavaVsCollector!="DIFFERENT"||
            f.TaskVsCollector!="DIFFERENT"||f.GSCProcessPrincipalVerified||
            f.DPAPICompatibilityVerified||f.LiveControlAuthorized||
            f.Risk!="INTERACTIVE_ACCOUNT_DIFFERS_NO_GO"{
            t.Fatalf("bad finding for %s: %+v",id,f)
        }
    }
}

func TestEvenSameInteractiveAccountCannotAttestGSCService(t *testing.T){
    m:=principalFixture()
    for i:=0;i<3;i++{
        e:=principalRow(m,i)
        e["task_principal_vs_collector"]="MATCH"
        e["udp_java_owner_vs_collector"]="MATCH"
    }
    p,err:=ReviewPrincipalScopeReport(asPrincipalJSON(m))
    if err!=nil{t.Fatal(err)}
    if p.SourceVerified||p.GSCProcessPrincipalVerified||p.DPAPICrossPrincipalCompatible||
        p.LiveControlAuthorized||p.CrossPrincipalSeparationObserved{
        t.Fatal("interactive account falsely treated as authenticated GSC service")
    }
}

func TestUnknownAccountRelationIsNotAPositiveProof(t *testing.T){
    m:=principalFixture()
    e:=principalRow(m,1)
    e["task_principal_resolved"]=false
    e["task_principal_vs_udp_java_owner"]="UNKNOWN"
    e["task_principal_vs_collector"]="UNKNOWN"
    e["result"]="PRINCIPAL_COMPARISON_INCOMPLETE_NO_GO"
    m["result"]="PRINCIPAL_SCOPE_EVIDENCE_INCOMPLETE_NO_GO"
    p,err:=ReviewPrincipalScopeReport(asPrincipalJSON(m))
    if err!=nil{t.Fatal(err)}
    if p.LiveControlAuthorized||p.GSCProcessPrincipalVerified||p.DPAPICrossPrincipalCompatible||
        len(p.Findings)!=3{t.Fatal("unknown account promoted to permission")}
}

func TestRejectContradictionsAndForgedAccountEvidence(t *testing.T){
    cases:=[]struct{
        name string
        mutate func(map[string]any)
    }{
        {"synthetic",func(m map[string]any){m["synthetic"]=true}},
        {"host_modified",func(m map[string]any){m["server_state_changed"]=true}},
        {"task_modified",func(m map[string]any){m["task_state_modified"]=true}},
        {"acl_modified",func(m map[string]any){m["acl_modified"]=true}},
        {"audit_changed",func(m map[string]any){m["audit_log_settings_changed"]=true}},
        {"dpapi_touched",func(m map[string]any){m["dpapi_access_attempted"]=true}},
        {"elevation",func(m map[string]any){m["privilege_elevation_attempted"]=true}},
        {"fake_auth",func(m map[string]any){m["source_authenticated"]=true}},
        {"fake_control",func(m map[string]any){m["live_control_authorized"]=true}},
        {"missing_read_only",func(m map[string]any){delete(m,"read_only")}},
        {"wrong_kind",func(m map[string]any){m["kind"]="FAKE"}},
        {"bad_collector_kind",func(m map[string]any){m["collector_account_kind"]="ADMINISTRATOR"}},
        {"unexpected_sid",func(m map[string]any){m["caller_sid"]="S-1-5-18"}},
        {"bad_clock",func(m map[string]any){m["collected_at_utc"]="nonsense"}},
        {"wrong_target",func(m map[string]any){principalRow(m,0)["id"]="lobby"}},
        {"duplicate_target",func(m map[string]any){principalRow(m,2)["id"]="wild"}},
        {"wrong_target_count",func(m map[string]any){m["instances"]=principalRows(m)[:2]}},
        {"unknown_relation",func(m map[string]any){principalRow(m,0)["java_parent_and_child_same_owner"]="SAME"}},
        {"fake_verified_identity",func(m map[string]any){principalRow(m,0)["reliable_task_to_jvm_identity_verified"]=true}},
        {"fake_dpapi",func(m map[string]any){principalRow(m,0)["dpapi_cross_process_compatibility_verified"]=true}},
        {"fake_entry_control",func(m map[string]any){principalRow(m,0)["live_control_authorized"]=true}},
        {"impossible_same_task_java_opposite_collector",func(m map[string]any){
            principalRow(m,0)["task_principal_vs_collector"]="MATCH"
        }},
        {"impossible_same_task_collector_different_java",func(m map[string]any){
            principalRow(m,0)["task_principal_vs_udp_java_owner"]="DIFFERENT"
        }},
        {"unresolved_account_claims_match",func(m map[string]any){
            principalRow(m,0)["task_principal_resolved"]=false
        }},
        {"unresolved_java_claims_match",func(m map[string]any){
            principalRow(m,0)["udp_java_owner_resolved"]=false
        }},
        {"wrong_row_classification",func(m map[string]any){
            principalRow(m,0)["result"]="SAFE_TO_RESTART"
        }},
        {"wrong_fleet_classification",func(m map[string]any){
            m["result"]="SAFE_TO_RESTART"
        }},
        {"missing_child_identity",func(m map[string]any){
            delete(principalRow(m,0),"udp_java_owner_resolved")
        }},
        {"user_secret_injected",func(m map[string]any){
            principalRow(m,0)["encrypted_key"]="dpapi-u:bad"
        }},
    }
    for _,tc:=range cases{
        t.Run(tc.name,func(t *testing.T){
            m:=principalFixture()
            tc.mutate(m)
            r,err:=ReviewPrincipalScopeReport(asPrincipalJSON(m))
            if err==nil{t.Fatalf("accepted invalid source evidence: %+v",r)}
            if r.LiveControlAuthorized{t.Fatal("invalid evidence allowed control")}
        })
    }
}
func TestRejectDuplicateKeysAndTrailingJSON(t *testing.T){
    original:=string(asPrincipalJSON(principalFixture()))
    for _,tc:=range []struct{name,source string}{
        {"empty",""},
        {"truncated",original[:len(original)-4]},
        {"too_large",strings.Repeat(" ",131073)},
        {"trailing",original+"{}"},
        {"dup_root",strings.Replace(original,`"schema":1`,`"schema":1,"schema":1`,1)},
        {"dup_nested",strings.Replace(original,`"task_running":true`,`"task_running":true,"task_running":true`,1)},
    }{
        t.Run(tc.name,func(t *testing.T){
            if _,err:=ReviewPrincipalScopeReport([]byte(tc.source));err==nil{
                t.Fatal("accepted malformed/ambiguous JSON")
            }
        })
    }
}
