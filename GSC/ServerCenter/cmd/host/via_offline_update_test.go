package main

import "testing"

func TestViaOfflineGateFailClosed(t *testing.T) {
 cases:=[]ServerStatus{
  {Online:true},{JavaPortOpen:true},{RCONPortOpen:true},
  {Java:JavaStats{PID:123}},{LauncherRunning:true},{DesiredRunning:true},
 }
 for _,tc:=range cases {
  if viaOfflineGate(tc)==nil {t.Errorf("unsafe state accepted: %+v",tc)}
 }
 if err:=viaOfflineGate(ServerStatus{});err!=nil {t.Fatal(err)}
}
func TestViaStageMatchRequiresExactComponentAndVersionedName(t *testing.T) {
 cases:=[]struct{component,file string;accept bool}{
  {"viaversion","ViaVersion-5.12.1.jar",true},
  {"viabackwards","ViaBackwards-5.12.1.jar",true},
  {"viaversion","ViaBackwards-5.12.1.jar",false},
  {"geyser","ViaVersion-5.12.1.jar",false},
  {"viaversion","ViaVersion.jar",false},
  {"viaversion","../../ViaVersion-5.12.1.jar",false},
 }
 for _,tc:=range cases{
  if got:=viaStageMatch(tc.component,tc.file);got!=tc.accept {
   t.Errorf("%s/%s: expected %v got %v",tc.component,tc.file,tc.accept,got)
  }
 }
}
