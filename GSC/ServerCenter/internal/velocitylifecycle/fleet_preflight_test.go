package velocitylifecycle

import (
 "encoding/json"
 "strings"
 "testing"
 "time"
)
func fixtureFleet() ([]ProxySnapshot,time.Time) {
 now:=time.Date(2026,10,18,3,0,0,0,time.UTC)
 return []ProxySnapshot{
  {Target:"wild",ObservedAt:now,TaskDefinitionMatches:true,TaskToParentIndependentlyAttested:true,
   ParentPID:101,ChildPID:102,ChildParentPID:101,UDPOwnerPID:102,TCPOwnerPID:102,TCPInventoryPresent:true,
   VelocitySHA256:velocity420Build30SHA,JavaStatusResponded:true,BedrockRaknetPong:true},
  {Target:"playground",ObservedAt:now,TaskDefinitionMatches:true,TaskToParentIndependentlyAttested:true,
   ParentPID:201,ChildPID:202,ChildParentPID:201,UDPOwnerPID:202,TCPOwnerPID:202,TCPInventoryPresent:true,
   VelocitySHA256:velocity420Build30SHA,JavaStatusResponded:true,BedrockRaknetPong:true},
  {Target:"other",ObservedAt:now,TaskDefinitionMatches:true,TaskToParentIndependentlyAttested:true,
   ParentPID:301,ChildPID:302,ChildParentPID:301,UDPOwnerPID:302,TCPOwnerPID:302,TCPInventoryPresent:true,
   VelocitySHA256:velocity420Build30SHA,JavaStatusResponded:true,BedrockRaknetPong:true},
 },now
}
func mustNeverAuthorize(t *testing.T,f FleetFinding) {
 t.Helper()
 if !f.ReadOnly||f.SourceVerified||f.SafeToExecute||len(f.Proxies)!=3 {t.Fatalf("unsafe fleet: %+v",f)}
 for _,p:=range f.Proxies {
  if p.SourceVerified||p.SafeToExecute {t.Fatalf("untrusted source promoted: %+v",p)}
 }
 b,err:=json.Marshal(f);if err!=nil{t.Fatal(err)}
 for _,field:=range []string{"parent_pid","child_pid","udp_owner_pid","tcp_owner_pid","ticket","path"} {
  if strings.Contains(string(b),"\""+field+"\"") {t.Fatalf("PID or path leaked: %s",field)}
 }
}
func TestFleetThreeProxyEvidenceCorrelatedButNeverAuthorizes(t *testing.T) {
 ss,now:=fixtureFleet();f:=InspectProxyFleet(ss,now);mustNeverAuthorize(t,f)
 if !f.AllThreePresent||!f.CrossProxyOwnersDistinct {t.Fatalf("valid fleet rejected: %+v",f)}
 for _,p:=range f.Proxies {
  if p.Classification!="snapshot_correlated_runtime_identity_still_unverified"||
   !p.OwnerCorrelationInSnapshot||!p.ArtifactMatchesReference||
   !p.PublicTCPResponded||!p.BedrockPongResponded||len(p.Reasons)!=0 {
   t.Fatalf("unexpected proxy classification: %+v",p)
  }
 }
}
func TestTCPProviderEmptyButIndependentJavaStatusResponds(t *testing.T) {
 ss,now:=fixtureFleet()
 for i:=range ss {ss[i].TCPInventoryPresent=false;ss[i].TCPOwnerPID=0}
 f:=InspectProxyFleet(ss,now);mustNeverAuthorize(t,f)
 for _,p:=range f.Proxies {
  if !p.TCPInventoryMissing||!p.PublicTCPResponded||
   p.Classification!="tcp_inventory_gap_java_application_responding"||len(p.Reasons)!=0 {
   t.Fatalf("missing Windows TCP table misinterpreted: %+v",p)
  }
 }
}
func TestFleetRejectsContradictoryOwnershipAndStaleSignals(t *testing.T) {
 cases:=[]struct{name string;edit func(*[]ProxySnapshot,*time.Time);reason string}{
  {"different_udp_owner",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].UDPOwnerPID=999},"udp_owner_or_process_lineage_conflict"},
  {"child_parent_drift",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].ChildParentPID=201},"udp_owner_or_process_lineage_conflict"},
  {"missing_child",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].ChildPID=0},"udp_owner_or_process_lineage_conflict"},
  {"same_parent_child",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].ChildPID=101},"udp_owner_or_process_lineage_conflict"},
  {"duplicate_across_proxies",func(s *[]ProxySnapshot,_ *time.Time){(*s)[1].ParentPID=102},"udp_owner_or_process_lineage_conflict"},
  {"task_not_correlated",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].TaskToParentIndependentlyAttested=false},"task_to_parent_identity_unverified"},
  {"task_definition_drift",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].TaskDefinitionMatches=false},"task_to_parent_identity_unverified"},
  {"wrong_jar",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].VelocitySHA256=strings.Repeat("a",64)},"jar_artifact_not_matching_reference"},
  {"absent_java_app_probe",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].JavaStatusResponded=false},"java_application_status_unverified"},
  {"absent_raknet",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].BedrockRaknetPong=false},"bedrock_raknet_unverified"},
  {"tcp_owner_conflict",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].TCPOwnerPID=333},"tcp_owner_conflict"},
  {"tcp_owner_zero",func(s *[]ProxySnapshot,_ *time.Time){(*s)[0].TCPOwnerPID=0},"tcp_owner_conflict"},
  {"stale_31s",func(s *[]ProxySnapshot,n *time.Time){(*s)[0].ObservedAt=n.Add(-31*time.Second)},"snapshot_stale_or_future"},
  {"future_1s",func(s *[]ProxySnapshot,n *time.Time){(*s)[0].ObservedAt=n.Add(time.Second)},"snapshot_stale_or_future"},
 }
 for _,tc:=range cases {
  t.Run(tc.name,func(t *testing.T){
   ss,now:=fixtureFleet();tc.edit(&ss,&now)
   f:=InspectProxyFleet(ss,now);mustNeverAuthorize(t,f)
   found:=false
   for _,p:=range f.Proxies {
    if p.Classification=="blocked_inconsistent_or_incomplete_evidence"&&
     strings.Contains(strings.Join(p.Reasons,","),tc.reason){found=true}
   }
   if !found {t.Fatalf("failed to block contradictory evidence: %+v",f)}
  })
 }
}
func TestIncompleteOrForgedFleetNeverBecomesHealthy(t *testing.T) {
 cases:=[]struct{name string; transform func([]ProxySnapshot)[]ProxySnapshot}{
  {"empty",func([]ProxySnapshot)[]ProxySnapshot{return nil}},
  {"missing_other",func(s []ProxySnapshot)[]ProxySnapshot{return s[:2]}},
  {"duplicate_wild",func(s []ProxySnapshot)[]ProxySnapshot{s[2]=s[0];return s}},
  {"extra_untrusted",func(s []ProxySnapshot)[]ProxySnapshot{return append(s,ProxySnapshot{Target:"unknown"})}},
 }
 for _,tc:=range cases {
  t.Run(tc.name,func(t *testing.T){
   ss,now:=fixtureFleet();f:=InspectProxyFleet(tc.transform(ss),now)
   mustNeverAuthorize(t,f)
   if f.AllThreePresent||f.CrossProxyOwnersDistinct {t.Fatalf("incomplete/fake fleet accepted: %+v",f)}
   for _,p:=range f.Proxies {
    if p.Classification=="snapshot_correlated_runtime_identity_still_unverified"||
     p.Classification=="tcp_inventory_gap_java_application_responding"{
     t.Fatalf("missing sibling accepted: %+v",p)
    }
   }
  })
 }
}
