package main

import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "testing"
)

func TestV5ReleaseReadOnlyContract(t *testing.T) {
 if appVersion!="5.0.0-beta.1" {t.Fatalf("Host version %q",appVersion)}
 for _,method:=range []string{http.MethodPost,http.MethodPut,http.MethodPatch,http.MethodDelete}{
  rec:=httptest.NewRecorder()
  apiV5ReleaseInfo(rec,httptest.NewRequest(method,"/api/v5/release",nil))
  if rec.Code!=http.StatusMethodNotAllowed{t.Fatalf("unexpected %s action: %d",method,rec.Code)}
 }
 rec:=httptest.NewRecorder()
 apiV5ReleaseInfo(rec,httptest.NewRequest(http.MethodGet,"/api/v5/release",nil))
 if rec.Code!=http.StatusOK || rec.Header().Get("Cache-Control")!="no-store"{t.Fatal("release API not read-only")}
 var v struct {
  OK bool `json:"ok"`
  Version string `json:"version"`
  Channel string `json:"channel"`
  APICompatibleMajor int `json:"api_compatible_major"`
  VelocityLifecycleOwner string `json:"velocity_lifecycle_owner"`
  Owns bool `json:"gsc_owns_velocity_processes"`
  AutoStable bool `json:"automatic_stable_promotion"`
 }
 if err:=json.Unmarshal(rec.Body.Bytes(),&v);err!=nil{t.Fatal(err)}
 if !v.OK||v.Version!="5.0.0-beta.1"||v.Channel!="beta"||v.APICompatibleMajor!=4||
  v.VelocityLifecycleOwner!="windows_task_scheduler"||v.Owns||v.AutoStable {
  t.Fatalf("unsafe release API contract: %+v",v)
 }
}
