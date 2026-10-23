package main

import (
 "bytes"
 "crypto/rand"
 "encoding/hex"
 "encoding/json"
 "errors"
 "io"
 "os"
 "path/filepath"
 "sync"
)

// The direct-ownership GSC Host process loses its private JVM stdin handle
// after the GSC service crashes/restarts. Never mistake "no local Controller"
// for proof no Java process survived. A durable per-target marker prevents
// silently launching a duplicate process even if its ports are not bound yet.
// The marker is intentionally NOT a kernel process identity attestation.
//
// There is NO automatic stale-marker deletion and NO force-kill fallback.
// Manual recovery must examine the real task/JVM before the owner can resume.
var ownedMarkerMu sync.Mutex
var ownedMarkerTokens=map[string]string{}

type ownedMarker struct {
 Schema int `json:"schema"`
 Target string `json:"target"`
 Generation string `json:"generation"`
}

func ownedMarkerFile(target,base string)(string,error){
 if !validManagedVelocityTarget(target)||base==""||!filepath.IsAbs(base){
  return "",errors.New("invalid private marker target/root")
 }
 folder:=filepath.Join(base,"GeumyiServerCenter","VelocityManaged","Recovery")
 fi,err:=os.Lstat(folder)
 if err!=nil||!fi.IsDir()||fi.Mode()&os.ModeSymlink!=0{
  return "",errors.New("protected migration archive is not a real directory")
 }
 return filepath.Join(folder,target+".active.json"),nil
}

func createOwnedMarker(target,base string)(string,error){
 path,err:=ownedMarkerFile(target,base)
 if err!=nil{return "",err}
 key:=make([]byte,24)
 if _,err=rand.Read(key);err!=nil{return "",errors.New("unavailable owner generation")}
 generation:=hex.EncodeToString(key)
 payload,err:=json.Marshal(ownedMarker{Schema:1,Target:target,Generation:generation})
 if err!=nil{return "",err}
 file,err:=os.OpenFile(path,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600)
 if err!=nil{return "",errors.New("previous or orphaned JVM generation needs recovery")}
 if _,err=file.Write(payload);err!=nil{
  _=file.Close()
  // Incomplete marker is intentionally retained to block unproven reuse.
  return "",errors.New("failed to persist private generation marker")
 }
 if err=file.Sync();err!=nil{
  _=file.Close()
  return "",errors.New("failed to sync private generation marker")
 }
 if err=file.Close();err!=nil{return "",errors.New("generation marker close failed")}
 return generation,nil
}

func readOwnedMarker(path string)(ownedMarker,error){
 var record ownedMarker
 data,err:=os.ReadFile(path)
 if err!=nil||len(data)<20||len(data)>2048{return record,errors.New("marker unreadable")}
 dec:=json.NewDecoder(bytesReader(data))
 dec.DisallowUnknownFields()
 if err=dec.Decode(&record);err!=nil{return record,errors.New("marker shape invalid")}
 if _,err=dec.Token();err!=io.EOF{return record,errors.New("marker has trailing JSON")}
 if record.Schema!=1||!validManagedVelocityTarget(record.Target)||
    len(record.Generation)!=48{
   return record,errors.New("invalid owned marker")
 }
 for _,c:=range record.Generation {
   if !((c>='0'&&c<='9')||(c>='a'&&c<='f')){
    return record,errors.New("bad marker generation")
   }
 }
 return record,nil
}

// Read into bytes.Reader without opening filesystem/network/process handles.
func bytesReader(data []byte)io.Reader{return bytes.NewReader(data)}

func releaseOwnedMarker(target,base,generation string)error{
 path,err:=ownedMarkerFile(target,base)
 if err!=nil{return err}
 record,err:=readOwnedMarker(path)
 if err!=nil{return err}
 if record.Target!=target||record.Generation!=generation{
  return errors.New("stale manager cannot delete a newer generation")
 }
 return os.Remove(path)
}

func ownedMarkerPresent(target,base string)bool{
 path,err:=ownedMarkerFile(target,base)
 if err!=nil{return true} // no readable archive is NOT a free lease
 _,err=os.Lstat(path)
 return err==nil||!os.IsNotExist(err)
}

func ownedMarkerAvailable(target string)bool{
 return !ownedMarkerPresent(target,os.Getenv("ProgramData"))
}

func beginManagedOwnedSession(target string)(func(success bool)error,error){
 ownedMarkerMu.Lock()
 defer ownedMarkerMu.Unlock()
 if _,running:=ownedMarkerTokens[target];running{
  return nil,errors.New("existing owner session active")
 }
 token,err:=createOwnedMarker(target,os.Getenv("ProgramData"))
 if err!=nil{return nil,err}
 ownedMarkerTokens[target]=token
 return func(success bool)error{
  if success{return nil}
  return finishManagedOwnedSession(target)
 },nil
}
func hasManagedOwnedSession(target string)bool{
 ownedMarkerMu.Lock()
 defer ownedMarkerMu.Unlock()
 token:=ownedMarkerTokens[target]
 if token==""{return false}
 path,err:=ownedMarkerFile(target,os.Getenv("ProgramData"))
 if err!=nil{return false}
 record,err:=readOwnedMarker(path)
 return err==nil&&record.Schema==1&&record.Target==target&&
  record.Generation==token
}
func finishManagedOwnedSession(target string)error{
 ownedMarkerMu.Lock()
 defer ownedMarkerMu.Unlock()
 token:=ownedMarkerTokens[target]
 if token==""{return errors.New("no trusted live owner generation")}
 if err:=releaseOwnedMarker(target,os.Getenv("ProgramData"),token);err!=nil{
  return err
 }
 delete(ownedMarkerTokens,target)
 return nil
}
