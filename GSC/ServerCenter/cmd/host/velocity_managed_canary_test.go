package main

import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "os"
 "path/filepath"
 "runtime"
 "strings"
 "testing"
)

func TestManagedVelocityCanaryDefaultLockedNoMutatingAction(t *testing.T){
 t.Setenv(velocityCanaryGate,"")
 for _,action:=range []string{"start","stop","restart","kill"}{
  request:=httptest.NewRequest(http.MethodPost,"/api/v1/velocity/managed/action",
      strings.NewReader(`{"target":"wild","action":"`+action+`","confirm":"`+velocityOperatorConfirm+`"}`))
  recorder:=httptest.NewRecorder()
  apiV1VelocityManagedAction(recorder,request)
  if recorder.Code!=http.StatusLocked {
   t.Fatalf("%s escaped default-disabled Canary gate: %d",action,recorder.Code)
  }
 }
 for _,method:=range []string{http.MethodGet,http.MethodPut,http.MethodPatch,http.MethodDelete}{
  request:=httptest.NewRequest(method,"/api/v1/velocity/managed/action",nil)
  rec:=httptest.NewRecorder()
  apiV1VelocityManagedAction(rec,request)
  if rec.Code!=http.StatusMethodNotAllowed{
    t.Fatalf("%s unexpectedly executed mutating Velocity handler",method)
  }
 }
}

func TestManagedVelocityStatusDefaultButtonsRemainDisabled(t *testing.T){
 t.Setenv(velocityCanaryGate,"")
 req:=httptest.NewRequest(http.MethodGet,"/api/v1/velocity/managed/status",nil)
 recorder:=httptest.NewRecorder()
 apiV1VelocityManagedStatus(recorder,req)
 if recorder.Code!=http.StatusOK||recorder.Header().Get("Cache-Control")!="no-store"{
  t.Fatal("safe canary status endpoint rejected")
 }
 var data struct{
  CanaryEnabled bool `json:"canary_enabled"`
  ReadOnly bool `json:"read_only"`
  Tasks []struct{
   Target string `json:"target"`
   LegacyTaskState string `json:"legacy_task_state"`
   CutoverReceiptVerified bool `json:"cutover_receipt_verified"`
   GSCManagedRunning bool `json:"gsc_managed_running"`
   CanStart bool `json:"can_start"`
   CanStop bool `json:"can_stop"`
   CanRestart bool `json:"can_restart"`
  } `json:"tasks"`
 }
 if err:=json.Unmarshal(recorder.Body.Bytes(),&data);err!=nil{t.Fatal(err)}
 if !data.ReadOnly||data.CanaryEnabled||len(data.Tasks)!=3{t.Fatal("default Canary capability gates bypassed")}
 for _,task:=range data.Tasks{
  if task.CanStart||task.CanStop||task.CanRestart||task.GSCManagedRunning||
      task.LegacyTaskState!="UNKNOWN"||task.CutoverReceiptVerified{
   t.Fatalf("default production host falsely offered active button: %+v",task)
  }
 }
 for _,method:=range []string{http.MethodPost,http.MethodPatch,http.MethodDelete}{
  rec:=httptest.NewRecorder()
  apiV1VelocityManagedStatus(rec,httptest.NewRequest(method,"/api/v1/velocity/managed/status",nil))
  if rec.Code!=http.StatusMethodNotAllowed{t.Fatalf("status unexpectedly accepts %s",method)}
 }
}

func TestManagedVelocityInvalidTargetAndManifestDoNotExecute(t *testing.T){
 t.Setenv(velocityCanaryGate,velocityCanaryValue)
 for _,target:=range []string{"","lobby","../../wild","WILD;STOP"}{
  if _,err:=managedVelocityController(target);err==nil{
    t.Fatalf("managed controller accepted %q",target)
  }
  if _,err:=readManagedVelocityManifest(target);err==nil{
    t.Fatalf("manifest accepted %q",target)
  }
 }
 if runtime.GOOS=="windows"{
  temp:=t.TempDir()
  t.Setenv("ProgramData",temp)
  if _,err:=readManagedVelocityManifest("wild");err==nil{
    t.Fatal("missing approval manifest accepted")
  }
  root:=filepath.Join(temp,"GeumyiServerCenter","VelocityManaged")
  if err:=os.MkdirAll(root,0700);err!=nil{t.Fatal(err)}
  for _,fixture:=range []string{
    `{"schema":1,"target":"wild","java_executable":"relative","working_directory":"relative","args":["-jar","velocity.jar"],"expected_jar_sha256":"bad"}`,
    `{"schema":1,"target":"wild","java_executable":"C:\\fake\\java.exe","working_directory":"C:\\bad","args":["-jar","velocity.jar"],"expected_jar_sha256":"bad"}`,
    `{"schema":1,"target":"wild","java_executable":"C:\\fake\\java.exe","working_directory":"C:\\bad","args":["-jar","velocity.jar"],"expected_jar_sha256":"bad","unexpected":"command"}`,
  }{
    path:=filepath.Join(root,"wild.json")
    if err:=os.WriteFile(path,[]byte(fixture),0600);err!=nil{t.Fatal(err)}
    if _,err:=readManagedVelocityManifest("wild");err==nil{
      t.Fatal("insecure or wrong-hash launcher accepted")
    }
  }
 }
}

func TestManagedCanaryNeverReportsControllerForUnknownTarget(t *testing.T){
 c,err:=managedVelocityController("wild")
 if err!=nil||c==nil{t.Fatal(err)}
 if c.Running(){t.Fatal("read-only canary unit tests somehow launched Velocity")}
}
