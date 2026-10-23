package main

import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "testing"
)

func TestVelocityTaskStatesSanitizedNoControl(t *testing.T){
  out:=buildVelocityTaskStatus(map[string]string{
    "wild":"Running","playground":"Ready","other":"Disabled",
    "lobby":"Running",
  })
  if !out.OK||!out.ReadOnly||out.ControlAuthorized||len(out.Tasks)!=3{
    t.Fatalf("invalid GSC Velocity status response: %+v",out)
  }
  for i,target:=range []string{"wild","playground","other"}{
    s:=out.Tasks[i]
    if s.Target!=target||s.CanStart||s.CanStop||s.CanRestart||
        s.JVMAuthenticated||s.PlayerSafetyVerified{
        t.Fatalf("unsafe scheduler status was turned into control: %+v",s)
    }
  }
  if !out.Tasks[0].RunningTask || out.Tasks[1].RunningTask || out.Tasks[2].RunningTask{
    t.Fatalf("scheduler states collapsed into false ONLINE inference: %+v",out.Tasks)
  }
}

func TestVelocityTaskObservationIsUnknownOnErrorsOrForgedStatuses(t *testing.T){
  for _,state:=range []string{"", "ERROR", "ONLINE", "RUNNING_AS_SYSTEM", "Restarting", "Succeeded"}{
    report:=buildVelocityTaskStatus(map[string]string{"wild":state})
    if report.Tasks[0].TaskState!="UNKNOWN"||report.Tasks[0].RunningTask||
       report.Tasks[0].CanStop||report.Tasks[0].CanRestart{
       t.Fatalf("untrusted task result must fail closed: %q %+v",state,report.Tasks[0])
    }
  }
}

func TestVelocityTaskStatusHandlerGETOnlyNoAction(t *testing.T){
  for _,method:=range []string{http.MethodPost,http.MethodPut,http.MethodPatch,http.MethodDelete}{
    req:=httptest.NewRequest(method,"/api/v1/velocity/tasks",nil)
    rec:=httptest.NewRecorder()
    apiV1VelocityTasks(rec,req)
    if rec.Code!=http.StatusMethodNotAllowed{
        t.Fatalf("%s mutation unexpectedly accepted: %d",method,rec.Code)
    }
  }
  // On non-Windows CI, the stub MUST return UNKNOWN; on Windows CI, no
  // production Day10 task names should exist and that stays UNKNOWN too.
  req:=httptest.NewRequest(http.MethodGet,"/api/v1/velocity/tasks",nil)
  rec:=httptest.NewRecorder()
  apiV1VelocityTasks(rec,req)
  if rec.Code!=http.StatusOK || rec.Header().Get("Cache-Control")!="no-store"{
    t.Fatalf("GET failed or caching mistakenly enabled: %d",rec.Code)
  }
  var out velocityTaskStatusResponse
  if err:=json.Unmarshal(rec.Body.Bytes(),&out);err!=nil{t.Fatal(err)}
  if !out.ReadOnly||out.ControlAuthorized||len(out.Tasks)!=3{
    t.Fatalf("GET status returned unsafe capability: %+v",out)
  }
  for _,item:=range out.Tasks{
    if item.CanStop||item.CanRestart||item.CanStart||
       item.JVMAuthenticated||item.PlayerSafetyVerified{
       t.Fatalf("status API wrongly granted lifecycle rights: %+v",item)
    }
  }
}
