package velocitylifecycle

import (
 "encoding/json"
 "strings"
 "testing"
)

func observedTaskPolicyFixture(count int) []byte {
 record:="POLICY_OBSERVED_LIVE_IDENTITY_UNVERIFIED"
 top:="TASK_POLICIES_CAPTURED_CONTROL_UNVERIFIED"
 if count>0 {record="AUTO_RESTART_RISK_NO_GO";top="AUTO_RESTART_RISK_PRESENT_NO_GO"}
 list:=make([]map[string]any,0,3)
 for _,id:=range []string{"wild","playground","other"} {
  list=append(list,map[string]any{
   "id":id,"task_present":true,"task_count":1,
   "task_definition_matches_expected":true,"task_state":"Running",
   "restart_policy_verified":true,"restart_count":count,
   "automatic_restart_configured":count>0,"multiple_instance_policy":"IgnoreNew",
   "task_to_jvm_identity_verified":false,"live_control_authorized":false,
   "result":record,
  })
 }
 data:=map[string]any{
  "schema":1,"kind":"GEUMYI_GSC_452_VELOCITY_TASK_RESTART_POLICY",
  "synthetic":false,"collected_at_utc":"2026-10-18T04:31:38.2060047+00:00",
  "server_state_changed":false,"scheduled_task_modified":false,
  "read_only":true,"live_control_authorized":false,
  "result":top,"instances":list,
 }
 b,err:=json.Marshal(data); if err!=nil {panic(err)}
 return b
}

func TestObservedTaskPolicyAllThree999AndIgnoreNewBlock(t *testing.T) {
 p,err:=ReviewTaskPolicyReport(observedTaskPolicyFixture(999));if err!=nil{t.Fatal(err)}
 if !p.ReadOnly||p.SourceVerified||p.LiveControlAuthorized||
  !p.AnyAutomaticRestart||p.Result!="BLOCKED_LIVE_CONTROL"||len(p.Findings)!=3 {
  t.Fatalf("unsafe real-shape report: %+v",p)
 }
 for i,id:=range []string{"wild","playground","other"} {
  f:=p.Findings[i]
  if f.Target!=id||f.RestartCount!=999||!f.AutomaticRestartConfigured||
   f.MultipleInstancePolicy!="IgnoreNew"||f.Risk!="AUTO_RESTART_RISK_NO_GO"||
   f.SafeToStart||f.SafeToStop||f.SafeToRestart {
   t.Fatalf("unsafe real-shape policy: %+v",f)
  }
 }
}

func TestZeroRestartsStillNoExecutionPermission(t *testing.T) {
 p,err:=ReviewTaskPolicyReport(observedTaskPolicyFixture(0));if err!=nil{t.Fatal(err)}
 if p.AnyAutomaticRestart||p.SourceVerified||p.LiveControlAuthorized {t.Fatalf("zero count became authorization")}
 for _,f:=range p.Findings {
  if f.SafeToStart||f.SafeToStop||f.SafeToRestart||f.Risk!="RESTART_POLICY_ZERO_STILL_NO_GO" {
   t.Fatalf("unsafe zero-restart finding: %+v",f)
  }
 }
}

func TestTaskPolicyCollectorAdversarialMutationsRejected(t *testing.T) {
 valid:=string(observedTaskPolicyFixture(999))
 replace:=func(old,newValue string)string {
  if !strings.Contains(valid,old){panic("test fixture replacement missing")}
  return strings.Replace(valid,old,newValue,1)
 }
 cases:=[]struct{name,source string}{
  {"empty",""},
  {"invalid_json",valid[:len(valid)-3]},
  {"oversized",strings.Repeat(" ",131073)},
  {"synthetic",replace("\"synthetic\":false","\"synthetic\":true")},
  {"report_claims_mutated",replace("\"server_state_changed\":false","\"server_state_changed\":true")},
  {"task_claims_modified",replace("\"scheduled_task_modified\":false","\"scheduled_task_modified\":true")},
  {"fake_authorization",replace("\"live_control_authorized\":false","\"live_control_authorized\":true")},
  {"missing_read_only",replace("\"read_only\":true,","")},
  {"wrong_kind",replace("GEUMYI_GSC_452_VELOCITY_TASK_RESTART_POLICY","WRONG")},
  {"duplicate_restart_key",replace("\"restart_count\":999","\"restart_count\":0,\"restart_count\":999")},
  {"duplicate_top_key",replace("\"schema\":1","\"schema\":1,\"schema\":1")},
  {"unknown_key",replace("\"schema\":1","\"schema\":1,\"unknown\":true")},
  {"unknown_target",replace("\"id\":\"wild\"","\"id\":\"lobby\"")},
  {"duplicate_target",replace("\"id\":\"other\"","\"id\":\"wild\"")},
  {"conflicting_count",replace("\"restart_count\":999","\"restart_count\":0")},
  {"missing_count",replace("\"restart_count\":999,","")},
  {"missing_identity_flag",replace("\"task_to_jvm_identity_verified\":false","\"missing\":false")},
  {"fake_identity_attestation",replace("\"task_to_jvm_identity_verified\":false","\"task_to_jvm_identity_verified\":true")},
  {"parallel_instances",replace("\"multiple_instance_policy\":\"IgnoreNew\"","\"multiple_instance_policy\":\"Parallel\"")},
  {"task_not_running",replace("\"task_state\":\"Running\"","\"task_state\":\"Ready\"")},
  {"wrong_top_result",replace("AUTO_RESTART_RISK_PRESENT_NO_GO","TASK_POLICIES_CAPTURED_CONTROL_UNVERIFIED")},
  {"trailing_json",valid+"{}"},
 }
 for _,tc:=range cases {
  t.Run(tc.name,func(t *testing.T){
   review,err:=ReviewTaskPolicyReport([]byte(tc.source))
   if err==nil {t.Fatalf("unsafe data accepted: %+v",review)}
   if review.LiveControlAuthorized {t.Fatalf("source untrusted but execution allowed")}
  })
 }
}
