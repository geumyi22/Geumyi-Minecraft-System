package main

import (
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
