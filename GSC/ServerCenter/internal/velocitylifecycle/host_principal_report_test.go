package velocitylifecycle

import (
 "encoding/json"
 "strings"
 "testing"
)

func hostPrincipalFixture() map[string]any {
  rows:=make([]any,0,3)
  for _,id:=range []string{"wild","playground","other"}{
    rows=append(rows,map[string]any{
      "id":id,"task_running":true,"task_principal_resolved":true,
      "host_vs_task_principal":"MATCH",
      "trusted_process_identity_verified":false,
      "dpapi_compatible":false,"live_control_authorized":false,
      "result":"GSC_HOST_TASK_ACCOUNT_RELATIONSHIP_ONLY_NO_GO",
    })
  }
  return map[string]any{
    "schema":1,"kind":"GEUMYI_GSC_452_HOST_RUNTIME_PRINCIPAL_READ_ONLY",
    "collected_at_utc":"2026-10-18T17:33:53.1172043+00:00",
    "synthetic":false,"read_only":true,
    "server_state_changed":false,"task_state_modified":false,
    "acl_modified":false,"dpapi_access_attempted":false,
    "event_log_settings_changed":false,
    "privilege_elevation_attempted":false,
    "source_authenticated":false,
    "host_executable_identity_verified":false,
    "gsc_service_runtime_attested":false,
    "live_control_authorized":false,
    "collector_vs_host":"DIFFERENT",
    "gsc_host_process_count_category":"ONE",
    "result":"GSC_HOST_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED",
    "instances":rows,
  }
}
func hostBytes(m map[string]any) []byte {
  b,err:=json.Marshal(m);if err!=nil{panic(err)};return b
}
func hostRow(m map[string]any,i int)map[string]any{
  return m["instances"].([]any)[i].(map[string]any)
}

func TestRealHostReportStillDeniesControlsAndCrossPrincipalDPAPI(t *testing.T){
  out,err:=ReviewHostPrincipalReport(hostBytes(hostPrincipalFixture()))
  if err!=nil{t.Fatal(err)}
  if !out.AllHostTaskSIDMatchHints||out.HostVsCollector!="DIFFERENT"||
    out.HostProcessCountCategory!="ONE"||out.SourceVerified||out.ExecutableVerified||
    out.GSCServiceRuntimeAttested||out.DPAPICompatible||out.LiveControlAuthorized||
    len(out.Findings)!=3{
    t.Fatalf("historical host/task SID match promoted to authority: %+v",out)
  }
  for i,id:=range []string{"wild","playground","other"}{
    x:=out.Findings[i]
    if x.Target!=id||!x.TaskRunning||x.HostVsTaskPrincipal!="MATCH"||
       x.Verified||x.DPAPICompatible||x.LiveControlAuthorized{
       t.Fatalf("%s host principal finding not fail-closed: %+v",id,x)
    }
  }
}
func TestHostAbsentOrMultipleRecordsAreAcceptedOnlyAsNoGo(t *testing.T){
  for _,state:=range []string{"NONE","MULTIPLE","UNKNOWN"}{
    t.Run(state,func(t *testing.T){
      m:=hostPrincipalFixture()
      m["gsc_host_process_count_category"]=state
      m["collector_vs_host"]="UNKNOWN"
      m["result"]="GSC_HOST_PRINCIPAL_SCOPE_UNVERIFIED_NO_GO"
      for i:=0;i<3;i++{
        x:=hostRow(m,i)
        x["host_vs_task_principal"]="UNKNOWN"
        x["result"]="GSC_HOST_PRINCIPAL_UNVERIFIED_NO_GO"
      }
      out,err:=ReviewHostPrincipalReport(hostBytes(m))
      if err!=nil{t.Fatal(err)}
      if out.AllHostTaskSIDMatchHints||out.LiveControlAuthorized||
        out.GSCServiceRuntimeAttested||out.DPAPICompatible{
        t.Fatal("unseen GSC host treated as verified")
      }
    })
  }
}
func TestRejectForgedHostEvidenceAndInconsistentHostState(t *testing.T){
  cases:=[]struct{name string;edit func(map[string]any)}{
    {"synthetic",func(m map[string]any){m["synthetic"]=true}},
    {"unknown_kind",func(m map[string]any){m["kind"]="FAKE"}},
    {"tampered_date",func(m map[string]any){m["collected_at_utc"]="false"}},
    {"host_modified",func(m map[string]any){m["server_state_changed"]=true}},
    {"task_modified",func(m map[string]any){m["task_state_modified"]=true}},
    {"ACL_modified",func(m map[string]any){m["acl_modified"]=true}},
    {"DPAPI_attempt",func(m map[string]any){m["dpapi_access_attempted"]=true}},
    {"eventlog_modified",func(m map[string]any){m["event_log_settings_changed"]=true}},
    {"elevated",func(m map[string]any){m["privilege_elevation_attempted"]=true}},
    {"forged_source",func(m map[string]any){m["source_authenticated"]=true}},
    {"forged_executable",func(m map[string]any){m["host_executable_identity_verified"]=true}},
    {"forged_service",func(m map[string]any){m["gsc_service_runtime_attested"]=true}},
    {"forged_control",func(m map[string]any){m["live_control_authorized"]=true}},
    {"forged_DPAPI",func(m map[string]any){hostRow(m,0)["dpapi_compatible"]=true}},
    {"forged_entry_control",func(m map[string]any){hostRow(m,0)["live_control_authorized"]=true}},
    {"forged_task_identity",func(m map[string]any){hostRow(m,0)["trusted_process_identity_verified"]=true}},
    {"missing_running",func(m map[string]any){delete(hostRow(m,0),"task_running")}},
    {"missing_resolved",func(m map[string]any){hostRow(m,0)["task_principal_resolved"]=false}},
    {"missing_collector_relation",func(m map[string]any){delete(m,"collector_vs_host")}},
    {"no_host_but_matches",func(m map[string]any){m["gsc_host_process_count_category"]="NONE"}},
    {"multiple_host_but_matches",func(m map[string]any){m["gsc_host_process_count_category"]="MULTIPLE"}},
    {"invalid_relation",func(m map[string]any){hostRow(m,2)["host_vs_task_principal"]="EQUAL"}},
    {"missing_task",func(m map[string]any){m["instances"]=m["instances"].([]any)[:2]}},
    {"duplicate_task",func(m map[string]any){hostRow(m,2)["id"]="wild"}},
    {"unknown_task",func(m map[string]any){hostRow(m,2)["id"]="lobby"}},
    {"claimed_restart",func(m map[string]any){m["result"]="SAFE_TO_RESTART"}},
    {"claimed_row",func(m map[string]any){hostRow(m,0)["result"]="SAFE_TO_RESTART"}},
    {"injected_SID",func(m map[string]any){hostRow(m,0)["ownerSID"]="S-1-5-18"}},
    {"injected_secret",func(m map[string]any){m["apiKey"]="not-here"}},
  }
  for _,tc:=range cases{
    t.Run(tc.name,func(t *testing.T){
      m:=hostPrincipalFixture()
      tc.edit(m)
      out,err:=ReviewHostPrincipalReport(hostBytes(m))
      if err==nil||out.LiveControlAuthorized{
        t.Fatalf("accepted forged host evidence %+v",out)
      }
    })
  }
}
func TestHostReportRejectsDuplicateJSONKeysAndTrailingPayload(t *testing.T){
  original:=string(hostBytes(hostPrincipalFixture()))
  bad:=[]string{
    "",original[:len(original)-3],original+"{}",
    strings.Repeat(" ",131073),
    strings.Replace(original,`"schema":1`,`"schema":1,"schema":1`,1),
    strings.Replace(original,`"task_running":true`,`"task_running":true,"task_running":true`,1),
  }
  for i,raw:=range bad{
    if out,err:=ReviewHostPrincipalReport([]byte(raw));err==nil{
      t.Fatalf("accepted invalid JSON fixture %d: %+v",i,out)
    }
  }
}
