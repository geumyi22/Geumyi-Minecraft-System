package main

import (
 "context"
 "crypto/subtle"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "errors"
 "fmt"
 "geumyi/servercenter/internal/velocitymanaged"
 "io"
 "net"
 "net/http"
 "os"
 "path/filepath"
 "runtime"
 "strings"
 "sync"
 "time"
)

// Managed-control Canary is OFF by default. NO legacy tasks are changed by
// this code. Operator must perform an approved migration and supply a locally
// protected per-target manifest; this host never accepts an executable path
// or command line from HTTP. It manages ONLY JVMs it has launched itself.
const velocityCanaryGate="GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN"
const velocityCanaryValue="DIRECT_OWNERSHIP_APPROVED"
const velocityOperatorConfirm="I_ACCEPT_VELOCITY_PLAYER_DISCONNECT"
const velocityJarPinnedSHA="35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8"

var managedVelocityLock sync.Mutex
var managedVelocityOwned=map[string]*velocitymanaged.Controller{}

func managedVelocityController(target string)(*velocitymanaged.Controller,error){
 managedVelocityLock.Lock();defer managedVelocityLock.Unlock()
 if existing,ok:=managedVelocityOwned[target];ok{return existing,nil}
 next,err:=velocitymanaged.New(target)
 if err!=nil{return nil,err}
 managedVelocityOwned[target]=next
 return next,nil
}

type velocityLocalManifest struct {
 Schema int `json:"schema"`
 Target string `json:"target"`
 JavaExecutable string `json:"java_executable"`
 WorkingDirectory string `json:"working_directory"`
 Args []string `json:"args"`
 ExpectedJarSHA256 string `json:"expected_jar_sha256"`
}

func velocityCanaryEnabled()bool{
 return runtime.GOOS=="windows"&&
   os.Getenv(velocityCanaryGate)==velocityCanaryValue
}
func trustedVelocityWorkdir(target string)string{
 if target!="wild"&&target!="playground"&&target!="other"{return ""}
 base:=os.Getenv("ProgramData")
 if base==""||!filepath.IsAbs(base){return ""}
 return filepath.Join(base,"GeumyiServerCenter","Network","FourServer",target)
}

func readManagedVelocityManifest(target string)(velocitymanaged.Spec,error){
 expectedDir:=trustedVelocityWorkdir(target)
 if !velocityCanaryEnabled()||expectedDir==""{
  return velocitymanaged.Spec{},errors.New("managed Velocity canary disabled")
 }
 manifestFile:=filepath.Join(os.Getenv("ProgramData"),
  "GeumyiServerCenter","VelocityManaged",target+".json")
 info,err:=os.Lstat(manifestFile)
 if err!=nil||!info.Mode().IsRegular()||info.Size()<20||info.Size()>8192{
  return velocitymanaged.Spec{},errors.New("operator-approved local Velocity manifest missing")
 }
 raw,err:=os.ReadFile(manifestFile)
 if err!=nil{return velocitymanaged.Spec{},errors.New("local manifest unreadable")}
 var manifest velocityLocalManifest
 dec:=json.NewDecoder(strings.NewReader(string(raw)))
 dec.DisallowUnknownFields()
 if err:=dec.Decode(&manifest);err!=nil{return velocitymanaged.Spec{},errors.New("bad manifest schema")}
 if err:=dec.Decode(new(any));err!=io.EOF{return velocitymanaged.Spec{},errors.New("extra manifest JSON")}
 if manifest.Schema!=1||manifest.Target!=target||
    !strings.EqualFold(filepath.Clean(manifest.WorkingDirectory),filepath.Clean(expectedDir))||
    !filepath.IsAbs(manifest.JavaExecutable)||
    !strings.EqualFold(filepath.Base(manifest.JavaExecutable),"java.exe")||
    !strings.EqualFold(manifest.ExpectedJarSHA256,velocityJarPinnedSHA)||
    len(manifest.Args)<2||len(manifest.Args)>40{
  return velocitymanaged.Spec{},errors.New("untrusted direct-ownership launcher")
 }
 java,err:=os.Lstat(manifest.JavaExecutable)
 if err!=nil||!java.Mode().IsRegular(){return velocitymanaged.Spec{},errors.New("pinned java executable unavailable")}
 // Reject shell/argfile side effects, JVM agents and alternate jar paths.
 jarArgCount:=0
 for i,arg:=range manifest.Args{
  if arg==""||strings.HasPrefix(arg,"@")||
     strings.ContainsAny(arg,"\r\n\x00")||
     strings.HasPrefix(strings.ToLower(arg),"-javaagent")||
     strings.HasPrefix(strings.ToLower(arg),"-agentlib")||
     strings.HasPrefix(strings.ToLower(arg),"-agentpath"){
    return velocitymanaged.Spec{},errors.New("unsafe Java launcher argument")
  }
  if arg=="-jar"{
    jarArgCount++
    if i+1>=len(manifest.Args)||manifest.Args[i+1]!="velocity.jar"{
      return velocitymanaged.Spec{},errors.New("Velocity jar must be pinned in workdir")
    }
  }
 }
 if jarArgCount!=1{return velocitymanaged.Spec{},errors.New("unexpected Java executable mode")}
 jar:=filepath.Join(expectedDir,"velocity.jar")
 jarInfo,err:=os.Lstat(jar)
 if err!=nil||!jarInfo.Mode().IsRegular(){return velocitymanaged.Spec{},errors.New("Velocity jar not regular")}
 stream,err:=os.Open(jar)
 if err!=nil{return velocitymanaged.Spec{},errors.New("Velocity jar unavailable")}
 h:=sha256.New()
 _,readErr:=io.Copy(h,stream)
 _=stream.Close()
 if readErr!=nil||hex.EncodeToString(h.Sum(nil))!=velocityJarPinnedSHA{
  return velocitymanaged.Spec{},errors.New("Velocity jar SHA does not match pinned verified artifact")
 }
 return velocitymanaged.Spec{
  Target:target,Executable:manifest.JavaExecutable,
  Args:append([]string(nil),manifest.Args...),
  WorkingDirectory:expectedDir,
 },nil
}

func managedTaskIsMigrated(target string,ctx context.Context)bool{
 // Task state Disabled is a NECESSARY, not sufficient, migration condition.
 // This cannot prove absence of orphan JVMs; Start additionally requires the
 // target's Java/Bedrock listeners to be free before launching.
 states:=observeVelocityTasks(ctx)
 return states[target]=="Disabled"&&velocityReceiptAvailable(target)
}

func freeManagedProxyPorts(target string)bool{
 var java,bedrock int
 switch target {
 case "wild":java,bedrock=25565,19132
 case "playground":java,bedrock=25566,19133
 case "other":java,bedrock=25567,19134
 default:return false
 }
 tcp,err:=net.Listen("tcp",fmt.Sprintf("0.0.0.0:%d",java))
 if err!=nil{return false}
 _=tcp.Close()
 udp,err:=net.ListenPacket("udp",fmt.Sprintf("0.0.0.0:%d",bedrock))
 if err!=nil{return false}
 _=udp.Close()
 return true
}

type managedVelocityRequest struct {
 Target string `json:"target"`
 Action string `json:"action"`
 Confirm string `json:"confirm"`
}

// This check deliberately bypasses the *classification* of requireAuth:
// with AllowLoopbackNoAuth=true, even a correctly authenticated loopback
// request is labelled "local" before its header is inspected. Managed
// lifecycle actions still require a valid explicit host token, not local
// network presence, a paired device token, or a browser cookie.
func velocityHostTokenValid(r *http.Request, expected string) bool {
 if r==nil||expected==""||!isLoopbackRemote(r.RemoteAddr){return false}
 token:=strings.TrimSpace(r.Header.Get("X-GSC-Token"))
 if token=="" {
  authorization:=strings.TrimSpace(r.Header.Get("Authorization"))
  if len(authorization)>=7&&strings.EqualFold(authorization[:7],"Bearer "){
   token=strings.TrimSpace(authorization[7:])
  }
 }
 if token==""||len(token)!=len(expected){return false}
 return subtle.ConstantTimeCompare([]byte(token),[]byte(expected))==1
}
// This route is registered behind requireAuth and is LOCKED on all currently
// deployed GSC builds. Even after manual Canary opt-in, only a host API token
// on loopback with an explicit disconnect confirmation may operate it.
// It never disables/updates/restores Scheduled Tasks or adopts foreign JVMs.
func apiV1VelocityManagedAction(w http.ResponseWriter,r *http.Request){
 if r.Method!=http.MethodPost{
  http.Error(w,"POST required",http.StatusMethodNotAllowed);return
 }
 if !velocityCanaryEnabled(){
  http.Error(w,"direct ownership not cut over",http.StatusLocked);return
 }
 if !velocityHostTokenValid(r,configSnapshot().APIToken){
  http.Error(w,"explicit local host API token required",http.StatusForbidden);return
 }
 var q managedVelocityRequest
 dec:=json.NewDecoder(http.MaxBytesReader(w,r.Body,2048))
 dec.DisallowUnknownFields()
 if err:=dec.Decode(&q);err!=nil{
  http.Error(w,"invalid action request",http.StatusBadRequest);return
 }
 if err:=dec.Decode(new(any));err!=io.EOF{
  http.Error(w,"extra action content",http.StatusBadRequest);return
 }
 if q.Confirm!=velocityOperatorConfirm||
   (q.Action!="start"&&q.Action!="stop"&&q.Action!="restart"){
  http.Error(w,"explicit maintenance and player disconnect consent required",http.StatusForbidden);return
 }
 controller,err:=managedVelocityController(q.Target)
 if err!=nil{
  http.Error(w,"unknown Velocity proxy",http.StatusBadRequest);return
 }
 if !managedTaskIsMigrated(q.Target,r.Context()){
  http.Error(w,"original task and private cutover receipt must verify migration",http.StatusConflict);return
 }
 permit:=velocitymanaged.StopPermit{Target:q.Target,OperatorApproved:true,
  TaskMigrationCompleted:true,AcceptPlayerDisconnects:true}
 var actionErr error
 switch q.Action{
 case "start":
  if controller.Running(){
   actionErr=velocitymanaged.ErrBusy
  }else if !freeManagedProxyPorts(q.Target){
   actionErr=errors.New("proxy port ownership is not free")
  }else{
   spec,e:=readManagedVelocityManifest(q.Target)
   if e!=nil {
    actionErr=e
   }else{
    // Atomic on-disk owner marker survives GSC host crashes. A stale owner
    // marker blocks duplicate Java launches even before a socket binds.
    release,e:=beginManagedOwnedSession(q.Target)
    if e!=nil {
     actionErr=e
    }else{
     actionErr=controller.Start(spec)
     if actionErr!=nil{
      if cleanupErr:=release(false);cleanupErr!=nil{
       actionErr=errors.New("launch failed and stale owner marker needs manual recovery")
      }
     }else{
      _=release(true)
     }
    }
   }
  }
 case "stop":
  if !hasManagedOwnedSession(q.Target){
   actionErr=errors.New("GSC owner generation not authenticated after host restart")
  }else{
   ctx,cancel:=context.WithTimeout(r.Context(),25*time.Second)
   defer cancel()
   actionErr=controller.GracefulStop(ctx,permit)
   if actionErr==nil{actionErr=finishManagedOwnedSession(q.Target)}
  }
 case "restart":
  // Validate original artifact hash and privileged launcher before player
  // disconnection. Preserve marker across the whole restart transition.
  if !hasManagedOwnedSession(q.Target) {
   actionErr=errors.New("GSC owner generation not authenticated after host restart")
  }else{
   spec,e:=readManagedVelocityManifest(q.Target)
   if e!=nil {
    actionErr=e
   }else{
    ctx,cancel:=context.WithTimeout(r.Context(),25*time.Second)
    defer cancel()
    actionErr=controller.RestartWithSpec(ctx,permit,spec)
   }
  }
 }
 if actionErr!=nil{
  http.Error(w,"managed Velocity action blocked or unconfirmed: "+actionErr.Error(),http.StatusConflict)
  return
 }
 w.Header().Set("Cache-Control","no-store")
 writeJSON(w,map[string]any{
  "ok":true,"target":q.Target,"action":q.Action,
  "gsc_owned_running":controller.Running(),
  "task_migration_required":true,
  "player_disconnect_approved":true,
 })
}


// Authenticated, sanitized, read-only presentation of the opted-in direct
// ownership state. No process/JVM is started or stopped by this handler.
func apiV1VelocityManagedStatus(w http.ResponseWriter,r *http.Request){
 if r.Method!=http.MethodGet{
  http.Error(w,"GET required",http.StatusMethodNotAllowed);return
 }
 enabled:=velocityCanaryEnabled()
 type row struct{
   Target string `json:"target"`
   GSCManagedRunning bool `json:"gsc_managed_running"`
   LegacyTaskDisabled bool `json:"legacy_task_disabled"`
   RecoveryRequired bool `json:"recovery_required"`
   CanStart bool `json:"can_start"`
   CanStop bool `json:"can_stop"`
   CanRestart bool `json:"can_restart"`
 }
 var tasks []row
 states:=map[string]string{}
 if enabled {states=observeVelocityTasks(r.Context())}
 for _,target:=range []string{"wild","playground","other"}{
  item:=row{Target:target,LegacyTaskDisabled:enabled&&states[target]=="Disabled"&&velocityReceiptAvailable(target)}
  if enabled {
   controller,e:=managedVelocityController(target)
   if e==nil{item.GSCManagedRunning=controller.Running()}
  }
  // Actual action request performs additional operator, manifest/port
  // preflight. A task being Disabled is not verified Java ownership.
  // A marker exists when this host owns or once owned a JVM. If its
  // host was restarted and the stdin handle lost, refuse duplicate Start.
  item.RecoveryRequired=enabled&&item.LegacyTaskDisabled&&
    !item.GSCManagedRunning&&!ownedMarkerAvailable(target)
  item.CanStart=enabled&&item.LegacyTaskDisabled&&!item.GSCManagedRunning&&
    ownedMarkerAvailable(target)
  item.CanStop=enabled&&item.LegacyTaskDisabled&&item.GSCManagedRunning&&
    hasManagedOwnedSession(target)
  item.CanRestart=item.CanStop
  tasks=append(tasks,item)
 }
 w.Header().Set("Cache-Control","no-store")
 writeJSON(w,map[string]any{
  "ok":true,"canary_enabled":enabled,
  "read_only":true,"operator_confirmation_required":true,
  "tasks":tasks,
 })
}
