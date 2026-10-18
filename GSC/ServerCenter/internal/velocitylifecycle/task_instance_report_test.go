package velocitylifecycle

import (
  "encoding/json"
  "strings"
  "testing"
)

func taskInstanceFixture(status string) []byte {
  list:=make([]map[string]any,0,3)
  for _,id:=range []string{"wild","playground","other"} {
    single:=status=="ONE_VISIBLE"
    count:=0
    if single {count=1}
    if status=="MULTIPLE_VISIBLE"{count=2}
    result:="TASK_INSTANCE_OR_JAVA_CORRELATION_UNVERIFIED"
    if single {result="ENGINE_PID_PAIR_HINT_NOT_AUTHENTICATED"}
    if status=="NO_VISIBLE_INSTANCE" {result="INSTANCE_NOT_VISIBLE_CONTEXT_UNVERIFIED"}
    list=append(list,map[string]any{
      "id":id, "task_running":true,
      "instance_query_status":status,"visible_instance_count":count,
      "engine_pid_present":single,"engine_pid_visible_as_process":single,
      "engine_pid_matches_java_parent":single,
      "engine_pid_matches_udp_java_child":false,
      "udp_java_pair_hint":true,"instance_to_jvm_suggestive":single,
      "reliable_task_to_jvm_identity_verified":false,
      "live_control_authorized":false,
      "safe_to_start":false,"safe_to_stop":false,"safe_to_restart":false,
      "result":result,
    })
  }
  raw:=map[string]any{
     "schema":1,"kind":"GEUMYI_GSC_452_VELOCITY_TASK_INSTANCE_COM_READ_ONLY",
     "collected_at_utc":"2026-10-18T09:20:18.9662913+00:00",
     "synthetic":false,"server_state_changed":false,
     "task_state_modified":false,"audit_log_settings_changed":false,
     "privilege_elevation_attempted":false,"read_only":true,
     "task_instance_source":"WINDOWS_TASKSCHD_COM_READ_ONLY",
     "source_authenticated":false,"live_control_authorized":false,
     "result":"TASK_INSTANCE_HINTS_UNVERIFIED_NO_GO",
     "instances":list,
  }
  b,err:=json.Marshal(raw);if err!=nil {panic(err)}
  return b
}

func TestTaskInstanceCOMHintsAreNeverLiveApproval(t *testing.T) {
  for _,status:=range []string{"ONE_VISIBLE","NO_VISIBLE_INSTANCE","MULTIPLE_VISIBLE","COM_UNAVAILABLE","COM_QUERY_FAILED_OR_ACCESS_DENIED"} {
    t.Run(status,func(t *testing.T){
      review,err:=ReviewTaskInstanceReport(taskInstanceFixture(status))
      if err!=nil {t.Fatal(err)}
      if review.Result!="BLOCKED_LIVE_CONTROL"||review.SourceVerified||review.LiveControlAuthorized||!review.ReadOnly||len(review.Findings)!=3 {
        t.Fatalf("untrusted COM evidence became authorization: %+v",review)
      }
      for i,id:=range []string{"wild","playground","other"} {
        f:=review.Findings[i]
        if f.Target!=id||f.ReliableTaskToJVMIdentityVerified||
          f.SafeToStart||f.SafeToStop||f.SafeToRestart {
          t.Fatalf("unsafe per-target result %+v",f)
        }
        if status=="ONE_VISIBLE" && (!f.EngineParentHint ||f.Risk!="ENGINE_PID_HINT_ONLY_NO_GO"){
          t.Fatalf("expected only an unauthenticated engine hint: %+v",f)
        }
      }
    })
  }
}

func TestTaskInstanceCOMRejectsUntrustedAndContradictoryReports(t *testing.T) {
  valid:=string(taskInstanceFixture("ONE_VISIBLE"))
  replace:=func(old,newValue string)string{
    if !strings.Contains(valid,old){panic("missing test anchor: "+old)}
    return strings.Replace(valid,old,newValue,1)
  }
  bad:=[]struct{name,body string}{
    {"empty",""},
    {"truncated",valid[:len(valid)-6]},
    {"oversized",strings.Repeat(" ",131073)},
    {"trailing",valid+"{}"},
    {"wrong_kind",replace("GEUMYI_GSC_452_VELOCITY_TASK_INSTANCE_COM_READ_ONLY","FAKE")},
    {"synthetic",replace("\"synthetic\":false","\"synthetic\":true")},
    {"bad_source",replace("WINDOWS_TASKSCHD_COM_READ_ONLY","REMOTE_INTERNET")},
    {"forged_auth",replace("\"source_authenticated\":false","\"source_authenticated\":true")},
    {"forged_live",replace("\"live_control_authorized\":false","\"live_control_authorized\":true")},
    {"log_mutation",replace("\"audit_log_settings_changed\":false","\"audit_log_settings_changed\":true")},
    {"task_mutation",replace("\"task_state_modified\":false","\"task_state_modified\":true")},
    {"privilege_elevation",replace("\"privilege_elevation_attempted\":false","\"privilege_elevation_attempted\":true")},
    {"forged_control",replace("\"safe_to_restart\":false","\"safe_to_restart\":true")},
    {"forged_identity",replace("\"reliable_task_to_jvm_identity_verified\":false","\"reliable_task_to_jvm_identity_verified\":true")},
    {"duplicate_key",replace("\"schema\":1","\"schema\":1,\"schema\":1")},
    {"nested_duplicate",replace("\"task_running\":true","\"task_running\":true,\"task_running\":true")},
    {"unknown_field",replace("\"schema\":1","\"schema\":1,\"engine_pid\":999")},
    {"bad_target",replace("\"id\":\"wild\"","\"id\":\"lobby\"")},
    {"duplicate_target",replace("\"id\":\"other\"","\"id\":\"wild\"")},
    {"multiple_count",replace("\"visible_instance_count\":1","\"visible_instance_count\":2")},
    {"missing_engine",replace("\"engine_pid_present\":true","\"engine_pid_present\":false")},
    {"not_visible_engine",replace("\"engine_pid_visible_as_process\":true","\"engine_pid_visible_as_process\":false")},
    {"no_pair",replace("\"udp_java_pair_hint\":true","\"udp_java_pair_hint\":false")},
    {"two_matches",replace("\"engine_pid_matches_udp_java_child\":false","\"engine_pid_matches_udp_java_child\":true")},
    {"false_suggestive",replace("\"instance_to_jvm_suggestive\":true","\"instance_to_jvm_suggestive\":false")},
    {"wrong_row_result",replace("ENGINE_PID_PAIR_HINT_NOT_AUTHENTICATED","TASK_INSTANCE_OR_JAVA_CORRELATION_UNVERIFIED")},
    {"wrong_top_result",replace("TASK_INSTANCE_HINTS_UNVERIFIED_NO_GO","SAFE")},
    {"missing_flag",replace("\"safe_to_stop\":false,","")},
    {"bad_timestamp",replace("2026-10-18T09:20:18.9662913+00:00","invalid_time")},
  }
  for _,tc:=range bad{
    t.Run(tc.name,func(t *testing.T){
      review,err:=ReviewTaskInstanceReport([]byte(tc.body))
      if err==nil {t.Fatalf("accepted invalid evidence: %+v",review)}
      if review.LiveControlAuthorized {t.Fatal("invalid evidence granted authority")}
    })
  }
}
