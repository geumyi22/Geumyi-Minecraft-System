package main

import (
 "net/http"
 "net/http/httptest"
 "strings"
 "testing"
)

func TestVelocityManagedRequiresExplicitLocalHostToken(t *testing.T){
 const expected="unit-test-host-api-token-not-a-real-secret"
 body:=`{"target":"wild","action":"stop","confirm":"I_ACCEPT_VELOCITY_PLAYER_DISCONNECT"}`
 for _,tc:=range []struct{name,remote,authorization,xToken string;allow bool}{
  {"no-token-loopback","127.0.0.1:8721","","",false},
  {"valid-bearer-loopback","127.0.0.1:8721","Bearer "+expected,"",true},
  {"valid-x-token-loopback","[::1]:8721","",expected,true},
  {"wrong-bearer-loopback","127.0.0.1:8721","Bearer wrong","",false},
  {"valid-token-remote","192.168.1.5:8721","Bearer "+expected,"",false},
  {"valid-token-ipv4-mapped-remote","203.0.113.2:8721","Bearer "+expected,"",false},
  {"device-token-loopback","127.0.0.1:8721","Bearer paired-device-key","",false},
  {"other-auth-scheme-loopback","127.0.0.1:8721","Basic "+expected,"",false},
  {"empty-bearer-loopback","127.0.0.1:8721","Bearer ","",false},
 }{
  t.Run(tc.name,func(t *testing.T){
   request:=httptest.NewRequest(http.MethodPost,"http://127.0.0.1/api/v1/velocity/managed/action",strings.NewReader(body))
   request.RemoteAddr=tc.remote
   if tc.authorization!=""{request.Header.Set("Authorization",tc.authorization)}
   if tc.xToken!=""{request.Header.Set("X-GSC-Token",tc.xToken)}
   if got:=velocityHostTokenValid(request,expected);got!=tc.allow{t.Fatalf("allow=%v got=%v",tc.allow,got)}
  })
 }
}

func TestVelocityManagedAPIRejectsMissingHostTokenBeforeAnySchedulerMutation(t *testing.T){
 t.Setenv(velocityCanaryGate,velocityCanaryValue)
 request:=httptest.NewRequest(http.MethodPost,"http://127.0.0.1/api/v1/velocity/managed/action",
  strings.NewReader(`{"target":"wild","action":"stop","confirm":"I_ACCEPT_VELOCITY_PLAYER_DISCONNECT"}`))
 request.RemoteAddr="127.0.0.1:9988"
 recorder:=httptest.NewRecorder()
 apiV1VelocityManagedAction(recorder,request)
 if recorder.Code!=http.StatusForbidden{t.Fatalf("missing local host token allowed: %d",recorder.Code)}
}
