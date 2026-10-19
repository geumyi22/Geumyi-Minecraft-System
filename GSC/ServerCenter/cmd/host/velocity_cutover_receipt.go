package main

import (
 "bytes"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "errors"
 "io"
 "os"
 "path/filepath"
 "regexp"
 "runtime"
 "unicode/utf16"
)

type velocityCutoverReceipt struct {
 Schema int `json:"schema"`
 Target string `json:"target"`
 Ticket string `json:"ticket"`
 OriginalSHA256 string `json:"original_sha256"`
 OriginalTaskState string `json:"original_task_state"`
 CutoverCommitted bool `json:"cutover_committed"`
 CreatedUTC string `json:"created_utc"`
}

var velocityTicketPattern=regexp.MustCompile("^[A-Z0-9-]{8,64}$")

func unicodeSHA256(s string)string {
 // Matches explicit PowerShell [Text.Encoding]::Unicode SHA-256 from the
 // local-only task XML snapshot, byte-for-byte (UTF-16 little-endian).
 chars:=utf16.Encode([]rune(s))
 buf:=make([]byte,len(chars)*2)
 for i,v:=range chars{
  buf[i*2]=byte(v)
  buf[i*2+1]=byte(v>>8)
 }
 sum:=sha256.Sum256(buf)
 return hex.EncodeToString(sum[:])
}

// loadVelocityCutoverReceipt validates the one-time, locally protected
// operator archive created by Velocity_Managed_Cutover.ps1. It is NOT a
// cryptographic process-identity or maintenance approval proof. Still require
// actual Scheduler state and independent port/process checks before Start.
// No task, filesystem ACL, Java process or key is modified by this function.
func loadVelocityCutoverReceipt(target string,base string)(bool,error){
 if !validManagedVelocityTarget(target) {
  return false,errors.New("unknown Velocity cutover target")
 }
 if base==""||!filepath.IsAbs(base){
  return false,errors.New("private ProgramData root unavailable")
 }
 folder:=filepath.Join(base,"GeumyiServerCenter","VelocityManaged","Recovery")
 receiptFile:=filepath.Join(folder,target+".receipt.json")
 originalFile:=filepath.Join(folder,target+".original.xml")
 for _,filename:=range []string{receiptFile,originalFile}{
  stat,err:=os.Lstat(filename)
  if err!=nil||!stat.Mode().IsRegular()||stat.Size()<20||stat.Size()>65536{
   return false,errors.New("private original task snapshot or receipt missing")
  }
 }
 receiptBytes,err:=os.ReadFile(receiptFile)
 if err!=nil{return false,errors.New("cutover receipt unreadable")}
 original,err:=os.ReadFile(originalFile)
 if err!=nil{return false,errors.New("original task XML unreadable")}
 if !utf8WellFormed(original) {
  return false,errors.New("original task XML is not UTF-8")
 }
 r,err:=parseVelocityCutoverReceipt(receiptBytes)
 if err!=nil{return false,err}
 if r.Schema!=1||r.Target!=target||
    !velocityTicketPattern.MatchString(r.Ticket)||
    (r.OriginalTaskState!="Running"&&r.OriginalTaskState!="Ready")||
    !r.CutoverCommitted ||
    !regexp.MustCompile("^[a-f0-9]{64}$").MatchString(r.OriginalSHA256) ||
    unicodeSHA256(string(original))!=r.OriginalSHA256{
    return false,errors.New("cutover has not been approved and verified")
 }
 return true,nil
}

func validManagedVelocityTarget(target string)bool{
 return target=="wild"||target=="playground"||target=="other"
}

func utf8WellFormed(data []byte)bool{
 // xml snapshot is expected to be UTF-8 from the operator kit.
 return bytes.Equal([]byte(string([]rune(string(data)))),data)
}

// Reject duplicate JSON keys and unknown receipt fields, as well as trailing
// JSON. This is a small fixed schema; it never executes an instruction.
func parseVelocityCutoverReceipt(data []byte)(velocityCutoverReceipt,error){
 deny:=func()(velocityCutoverReceipt,error){
  return velocityCutoverReceipt{},errors.New("invalid or ambiguous cutover receipt")
 }
 if len(data)==0||len(data)>8192{return deny()}
 dec:=json.NewDecoder(bytes.NewReader(data))
 token,err:=dec.Token()
 if err!=nil||token!=json.Delim('{'){return deny()}
 seen:=make(map[string]json.RawMessage,7)
 for dec.More(){
  key,err:=dec.Token()
  if err!=nil{return deny()}
  name,ok:=key.(string)
  if !ok{return deny()}
  if _,duplicate:=seen[name];duplicate{return deny()}
  var value json.RawMessage
  if err=dec.Decode(&value);err!=nil{return deny()}
  seen[name]=value
 }
 end,err:=dec.Token()
 if err!=nil||end!=json.Delim('}'){return deny()}
 if _,err=dec.Token();err!=io.EOF{return deny()}
 if len(seen)!=7{return deny()}
 for _,key:=range []string{"schema","target","ticket","original_sha256","original_task_state","cutover_committed","created_utc"}{
  if _,exists:=seen[key];!exists{return deny()}
 }
 dec2:=json.NewDecoder(bytes.NewReader(data))
 dec2.DisallowUnknownFields()
 var receipt velocityCutoverReceipt
 if err=dec2.Decode(&receipt);err!=nil{return deny()}
 if receipt.CreatedUTC==""{return deny()}
 return receipt,nil
}

// The feature is still unavailable on non-Windows installations.
func velocityReceiptAvailable(target string)bool{
 if runtime.GOOS!="windows"{return false}
 ok,_:=loadVelocityCutoverReceipt(target,os.Getenv("ProgramData"))
 return ok
}
