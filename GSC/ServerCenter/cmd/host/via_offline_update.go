package main

import (
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "net/http"
 "os"
 "path/filepath"
 "strings"
 "time"
)

// Via plugins belong to Paper backend servers. Unlike Geyser/Floodgate,
// staged Via jars are applied only while every managed backend is offline.
// No Minecraft process is stopped/started by this handler.
func viaOfflineGate(st ServerStatus) error {
 if st.Online || st.JavaPortOpen || st.RCONPortOpen || st.Java.PID>0 || st.LauncherRunning || st.DesiredRunning {
  return errors.New("backend is still running or requested to run")
 }
 return nil
}
func viaStageMatch(component,file string) bool {
 m:=externalVersionRE.FindStringSubmatch(file)
 return len(m)==3 && strings.EqualFold(m[1],component) && (component=="viaversion"||component=="viabackwards")
}
type viaOp struct{ old,new,backup,staged,sha,server string }
func applyExternalViaOffline(plan externalStagePlanFile)(map[string]any,error){
 type item struct{component,file,sha string}
 var requested []item
 seen:=map[string]bool{}
 for _,s:=range plan.Staged {
  if s.Component!="viaversion"&&s.Component!="viabackwards"{continue}
  if seen[s.Component]||!viaStageMatch(s.Component,s.File){return nil,errors.New("invalid duplicate Via stage")}
  seen[s.Component]=true
  requested=append(requested,item{s.Component,s.File,s.SHA256})
 }
 if len(requested)==0{return nil,errors.New("no staged Via JAR found")}
 servers:=configSnapshot().Servers
 if len(servers)==0{return nil,errors.New("no managed backend servers")}
 backups:=filepath.Join(v4Root(),"Backups","ViaOffline-"+time.Now().Format("20060102-150405"))
 var ops []viaOp
 for _,raw:=range servers{
  s:=normalizeServerConfig(raw)
  if err:=viaOfflineGate(getServerStatus(s));err!=nil{return nil,fmt.Errorf("%s: %w",s.ID,err)}
  dir:=resolveServerDir(s)
  if dir==""{return nil,fmt.Errorf("%s: invalid server directory",s.ID)}
  plugins:=filepath.Join(dir,"plugins")
  info,err:=os.Lstat(plugins)
  if err!=nil||!info.IsDir()||info.Mode()&os.ModeSymlink!=0{return nil,fmt.Errorf("%s: invalid plugins directory",s.ID)}
  entries,err:=os.ReadDir(plugins);if err!=nil{return nil,err}
  for _,req:=range requested{
   old:=""
   for _,e:=range entries{
    if e.IsDir()||!viaStageMatch(req.component,e.Name()){continue}
    if old!=""{return nil,fmt.Errorf("%s: duplicate %s jars; manual review required",s.ID,req.component)}
    old=filepath.Join(plugins,e.Name())
    oldInfo,err:=os.Lstat(old)
    if err!=nil||!oldInfo.Mode().IsRegular(){return nil,fmt.Errorf("%s: unsafe existing JAR",s.ID)}
   }
   if old==""{return nil,fmt.Errorf("%s: missing installed %s",s.ID,req.component)}
   stage:=filepath.Join(plan.Root,req.file)
   hash,err:=fileSHA256(stage)
   if err!=nil||!strings.EqualFold(hash,req.sha){return nil,fmt.Errorf("%s: staged SHA mismatch",req.component)}
   ops=append(ops,viaOp{old:old,new:filepath.Join(plugins,req.file),backup:filepath.Join(backups,s.ID,filepath.Base(old)),staged:stage,sha:req.sha,server:s.ID})
  }
 }
 // No live mutation until all legacy files are backed up and hash-verified.
 for _,op:=range ops{
  if err:=externalAtomicCopy(op.old,op.backup);err!=nil{return nil,fmt.Errorf("backup failed; no live changes: %w",err)}
  a,e1:=fileSHA256(op.old);b,e2:=fileSHA256(op.backup)
  if e1!=nil||e2!=nil||a!=b{return nil,errors.New("backup checksum failed; live unchanged")}
 }
 for _,raw:=range servers{
  if err:=viaOfflineGate(getServerStatus(normalizeServerConfig(raw)));err!=nil{
   return nil,fmt.Errorf("backend went online; no live changes: %w",err)
  }
 }
 changed:=[]viaOp{}
 var failure error
 for _,op:=range ops{
  changed=append(changed,op)
  if e:=os.Remove(op.old);e!=nil{failure=e;break}
  if e:=externalAtomicCopy(op.staged,op.new);e!=nil{failure=e;break}
  got,e:=fileSHA256(op.new)
  if e!=nil||!strings.EqualFold(got,op.sha){failure=fmt.Errorf("installed Via checksum failed");break}
 }
 if failure!=nil{
  var rollbackProblems []string
  for i:=len(changed)-1;i>=0;i--{
   op:=changed[i]
   if op.old!=op.new{_ = os.Remove(op.new)}
   if e:=externalAtomicCopy(op.backup,op.old);e!=nil{rollbackProblems=append(rollbackProblems,e.Error())}
  }
  appendV4Event("error","update","","Via offline rollback",fmt.Sprintf("error=%v rollback=%v backup=%s",failure,rollbackProblems,backups))
  return nil,fmt.Errorf("apply failed: %v; rollback=%v; backup=%s",failure,rollbackProblems,backups)
 }
 appendV4Event("info","update","","Via offline JAR update staged to live folder",fmt.Sprintf("files=%d backup=%s requires_server_start=true",len(ops),backups))
 return map[string]any{"ok":true,"files":len(ops),"backup_root":backups,"restart_required":true,"health_verified":false,"server_started":false},nil
}
func apiV4ExternalUpdateViaOffline(w http.ResponseWriter,r *http.Request){
 if r.Method!=http.MethodPost{http.Error(w,"POST required",http.StatusMethodNotAllowed);return}
 var q struct{Root string `json:"root"`; Confirm string `json:"confirm"`}
 if err:=json.NewDecoder(io.LimitReader(r.Body,1<<20)).Decode(&q);err!=nil{http.Error(w,"invalid json",http.StatusBadRequest);return}
 if q.Confirm!="APPLY_VIA_OFFLINE"{http.Error(w,"explicit offline confirmation required",http.StatusConflict);return}
 if !updateApplyMu.TryLock(){http.Error(w,"another update is in progress",http.StatusConflict);return}
 defer updateApplyMu.Unlock()
 plan,err:=readExternalStagePlan(q.Root);if err!=nil{http.Error(w,err.Error(),http.StatusConflict);return}
 res,err:=applyExternalViaOffline(plan);if err!=nil{http.Error(w,err.Error(),http.StatusConflict);return}
 writeJSON(w,res)
}
