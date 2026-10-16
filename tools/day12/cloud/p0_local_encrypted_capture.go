//go:build ignore

// Day12 P0: constrained *local* encrypted settings capture, never cloud upload.
// Operator inputs are a single private UTF-8 JSON message on stdin, NOT arguments.
// No passwords, full source paths or plaintext contents are echoed/logged.
// The separate Windows wrapper must independently validate all source paths and
// the staging location. No live-world consistency or full recovery claim.
package main

import (
 "bytes"
 "crypto/aes"
 "crypto/cipher"
 "crypto/hmac"
 "crypto/rand"
 "crypto/sha256"
 "encoding/base64"
 "encoding/hex"
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "os"
 "path/filepath"
 "sort"
 "strings"
 "time"
)

const version = 1
const iterations = 450000
const maximumOneFile = 8 * 1024 * 1024
const maximumTotal = 48 * 1024 * 1024

type candidate struct {
 Name string `json:"name"`
 Source string `json:"source"`
}
type request struct {
 Passphrase string `json:"passphrase"`
 Dest string `json:"dest"`
 Files []candidate `json:"files"`
}
type archiveHeader struct {
 Schema int `json:"schema"`
 KDF string `json:"kdf"`
 Iterations int `json:"iterations"`
 Salt string `json:"salt"`
 ArchiveID string `json:"archive_id"`
}
type partRecord struct {
 Name string `json:"name"`
 Part string `json:"part"`
 Size int `json:"size"`
 SHA256 string `json:"sha256"`
}
type manifest struct {
 Schema int `json:"schema"`
 Files []partRecord `json:"files"`
}
func fail(msg string) error { return errors.New(msg) }
func digest(input []byte) string { s:=sha256.Sum256(input);return hex.EncodeToString(s[:]) }
func randomN(n int) ([]byte,error) { b:=make([]byte,n);_,e:=io.ReadFull(rand.Reader,b);return b,e }
func pbkdf2SHA256(password,salt []byte, rounds,keyLen int) []byte {
 const hLen=32
 out:=make([]byte,0,keyLen)
 for i:=uint32(1);len(out)<keyLen;i++{
  h:=hmac.New(sha256.New,password)
  _,_=h.Write(salt)
  _,_=h.Write([]byte{byte(i>>24),byte(i>>16),byte(i>>8),byte(i)})
  u:=h.Sum(nil);t:=append([]byte(nil),u...)
  for j:=1;j<rounds;j++{
   h=hmac.New(sha256.New,password)
   _,_=h.Write(u)
   u=h.Sum(nil)
   for k:=0;k<hLen;k++{t[k]^=u[k]}
  }
  out=append(out,t...)
 }
 return out[:keyLen]
}
func aeadFor(passphrase string,h archiveHeader) (cipher.AEAD,error) {
 if h.Schema!=version || h.KDF!="PBKDF2-HMAC-SHA256" ||
    h.Iterations!=iterations || len(h.ArchiveID)!=32{return nil,fail("INVALID_HEADER")}
 salt,e:=base64.RawStdEncoding.DecodeString(h.Salt)
 if e!=nil || len(salt)!=24{return nil,fail("INVALID_SALT")}
 if _,e=hex.DecodeString(h.ArchiveID);e!=nil{return nil,fail("INVALID_ARCHIVE_ID")}
 key:=pbkdf2SHA256([]byte(passphrase),salt,h.Iterations,32)
 defer clear(key)
 block,e:=aes.NewCipher(key);if e!=nil{return nil,fail("INVALID_CIPHER")}
 return cipher.NewGCM(block)
}
func safeName(name string) bool {
 if name=="" || strings.IndexByte(name,92)>=0 || strings.IndexByte(name,58)>=0 ||
    strings.IndexByte(name,0)>=0 || strings.IndexByte(name,13)>=0 || strings.IndexByte(name,10)>=0 ||
    strings.HasPrefix(name,"/") || strings.Contains(name,"..") ||
    filepath.Clean(name)!=filepath.FromSlash(name){return false}
 chunks:=strings.Split(name,"/")
 if len(chunks)<2{return false}
 for _,v:=range chunks {if v=="" || v=="." || v==".." || strings.HasSuffix(v,"."){return false}}
 if name=="gsc/server.json"{return true}
 if len(chunks)<3{return false}
 tail:=strings.Join(chunks[2:],"/")
 switch chunks[0]{
 case "paper":
  switch chunks[1]{case "wild","playground","other","lobby": default:return false}
  return tail=="server.properties"
 case "proxy":
  switch chunks[1]{case "wild","playground","other":default:return false}
  switch tail {
   case "velocity.toml","forwarding.secret","plugins/Geyser-Velocity/config.yml",
    "plugins/floodgate/config.yml","plugins/floodgate/key.pem":
    return true
  }
 }
 return false
}
func requiredNames() []string {
 v:=[]string{"gsc/server.json"}
 for _,r:=range []string{"wild","playground","other","lobby"}{
  v=append(v,"paper/"+r+"/server.properties")
 }
 for _,r:=range []string{"wild","playground","other"}{
  for _,f:=range []string{"velocity.toml","forwarding.secret","plugins/Geyser-Velocity/config.yml",
   "plugins/floodgate/config.yml","plugins/floodgate/key.pem"}{
   v=append(v,"proxy/"+r+"/"+f)
  }
 }
 return v
}
func checkInput(req request) ([]candidate,error) {
 if len([]rune(req.Passphrase))<20 || len([]rune(req.Passphrase))>256{
  return nil,fail("RECOVERY_PASSPHRASE_LENGTH_REJECTED")
 }
 if len(req.Files)!=len(requiredNames()){return nil,fail("P0_EXACT_SET_REQUIRED")}
 found:=map[string]bool{}
 files:=append([]candidate(nil),req.Files...)
 for _,f:=range files {
  if !safeName(f.Name) || found[strings.ToLower(f.Name)]{return nil,fail("P0_UNSAFE_OR_DUPLICATE_NAME")}
  found[strings.ToLower(f.Name)]=true
  if !filepath.IsAbs(f.Source) || strings.IndexByte(f.Source,0)>=0 {
   return nil,fail("P0_SOURCE_ABSOLUTE_PATH_REQUIRED")
  }
 }
 for _,name:=range requiredNames() {
  if !found[strings.ToLower(name)]{return nil,fail("P0_MISSING_REQUIRED_NAME")}
 }
 sort.Slice(files,func(i,j int)bool{return files[i].Name<files[j].Name})
 return files,nil
}
func stagingDirectory(dest string) error {
 local:=os.Getenv("LOCALAPPDATA")
 if local=="" || dest=="" || !filepath.IsAbs(dest){return fail("LOCAL_STAGING_REQUIRED")}
 localAbs,e:=filepath.Abs(local);if e!=nil{return fail("LOCAL_STAGING_INVALID")}
 destAbs,e:=filepath.Abs(dest);if e!=nil{return fail("DESTINATION_INVALID")}
 expectedParent:=filepath.Join(localAbs,"Geumyi-P0-Encrypted-Staging")
 actualParent:=filepath.Dir(destAbs)
 if !strings.EqualFold(actualParent,expectedParent) ||
    !strings.HasPrefix(filepath.Base(destAbs),"P0-"+ "") ||
    len(filepath.Base(destAbs))<20 {return fail("DESTINATION_OUTSIDE_FIXED_LOCAL_STAGING")}
 // The wrapper refuses provider roots; the binary checks all destination
 // ancestors are ordinary directories, not symlinks, junctions or cloud FS.
 walk:=localAbs
 for _,p:=range []string{walk,expectedParent}{
  s,e:=os.Lstat(p)
  if e!=nil && os.IsNotExist(e) && p==expectedParent{
   if e=os.Mkdir(p,0700);e!=nil{return fail("STAGING_PARENT_CREATE_FAILED")}
   s,e=os.Lstat(p)
  }
  if e!=nil || !s.IsDir() || s.Mode()&os.ModeSymlink!=0 {
   return fail("STAGING_ANCESTOR_UNVERIFIED")
  }
 }
 // Explicit NEW directory, no reuse or overwrite.
 if e=os.Mkdir(destAbs,0700);e!=nil{return fail("DESTINATION_EXISTS_OR_UNAVAILABLE")}
 return nil
}
func writeExclusive(path string,b []byte) error {
 file,e:=os.OpenFile(path,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600)
 if e!=nil{return fail("EXCLUSIVE_OUTPUT_CREATION_FAILED")}
 _,w:=file.Write(b);c:=file.Close()
 if w!=nil || c!=nil{return fail("OUTPUT_WRITE_FAILED")}
 return nil
}
func encrypt(aead cipher.AEAD,plain []byte,aad []byte) ([]byte,error){
 nonce,e:=randomN(aead.NonceSize());if e!=nil{return nil,fail("NONCE_RANDOMNESS_FAILURE")}
 return append(nonce,aead.Seal(nil,nonce,plain,aad)...),nil
}
func decrypt(aead cipher.AEAD,input,aad []byte)([]byte,error){
 if len(input)<aead.NonceSize()+aead.Overhead(){return nil,fail("CIPHERTEXT_SHORT")}
 pt,e:=aead.Open(nil,input[:aead.NonceSize()],input[aead.NonceSize():],aad)
 if e!=nil{return nil,fail("CIPHERTEXT_AUTH_FAILED")}
 return pt,nil
}
func safeRegular(path string) (os.FileInfo,error) {
 st,e:=os.Lstat(path)
 if e!=nil || !st.Mode().IsRegular(){return nil,fail("SOURCE_FILE_NOT_REGULAR_OR_MISSING")}
 if st.Size()<1 || st.Size()>maximumOneFile{return nil,fail("SOURCE_FILE_SIZE_OUTSIDE_P0")}
 return st,nil
}
func readBoundedSource(path string) ([]byte,error) {
 before,e:=safeRegular(path);if e!=nil{return nil,e}
 f,e:=os.Open(path);if e!=nil{return nil,fail("SOURCE_OPEN_OR_HYDRATION_FAILED")}
 b,e:=io.ReadAll(io.LimitReader(f,maximumOneFile+1))
 c:=f.Close()
 if e!=nil || c!=nil || len(b)<1 || len(b)>maximumOneFile{
  return nil,fail("SOURCE_READ_FAILED_OR_OVERSIZED")
 }
 after,e:=safeRegular(path)
 if e!=nil || before.Size()!=after.Size() || before.ModTime()!=after.ModTime() ||
  int64(len(b))!=after.Size(){return nil,fail("SOURCE_CHANGED_DURING_READ")}
 return b,nil
}
func addEncryptedFiles(req request) (string,error){
 files,e:=checkInput(req);if e!=nil{return "",e}
 if e=stagingDirectory(req.Dest);e!=nil{return "",e}
 // Once stagingDirectory creates a new directory, every failure leaves it
 // INCOMPLETE. No automatic deletion, no source modification.
 salt,e:=randomN(24);if e!=nil{return "",fail("SALT_RANDOMNESS_FAILURE")}
 id,e:=randomN(16);if e!=nil{return "",fail("ARCHIVE_ID_RANDOMNESS_FAILURE")}
 h:=archiveHeader{Schema:version,KDF:"PBKDF2-HMAC-SHA256",Iterations:iterations,
  Salt:base64.RawStdEncoding.EncodeToString(salt),ArchiveID:hex.EncodeToString(id)}
 a,e:=aeadFor(req.Passphrase,h);if e!=nil{return "",e}
 manifestObject:=manifest{Schema:version,Files:[]partRecord{}}
 count:=0
 keyHashes:=map[string]string{}
 for i,f:=range files {
  b,err:=readBoundedSource(f.Source);if err!=nil{return "",err}
  count+=len(b);if count>maximumTotal{return "",fail("P0_TOTAL_SIZE_EXCEEDED")}
  name:=fmt.Sprintf("part-%03d.gcm",i)
  aad:=[]byte(fmt.Sprintf("p0/file/v1/%s/%d/%s",h.ArchiveID,i,f.Name))
  enc,err:=encrypt(a,b,aad);if err!=nil{return "",err}
  if err=writeExclusive(filepath.Join(req.Dest,name),enc);err!=nil{return "",err}
  if strings.HasPrefix(f.Name,"proxy/") {
   group:=""
   if strings.HasSuffix(f.Name,"/forwarding.secret"){group="forwarding"}
   if strings.HasSuffix(f.Name,"/plugins/floodgate/key.pem"){group="floodgate"}
   if group!=""{
    hashed:=digest(b)
    if original,ok:=keyHashes[group];ok && original!=hashed{
     return "",fail("THREE_PROXY_KEYS_DIFFER_AT_CAPTURE")
    }
    keyHashes[group]=hashed
   }
  }
  manifestObject.Files=append(manifestObject.Files,partRecord{
   Name:f.Name,Part:name,Size:len(b),SHA256:digest(b)})
  clear(b)
 }
 mb,e:=json.Marshal(manifestObject);if e!=nil{return "",fail("MANIFEST_ENCODE_FAILED")}
 sealed,e:=encrypt(a,mb,[]byte("p0/manifest/v1/"+h.ArchiveID))
 if e!=nil{return "",e}
 if e=writeExclusive(filepath.Join(req.Dest,"manifest.gcm"),sealed);e!=nil{return "",e}
 hb,e:=json.Marshal(h);if e!=nil{return "",fail("HEADER_ENCODE_FAILED")}
 if e=writeExclusive(filepath.Join(req.Dest,"header.json"),hb);e!=nil{return "",e}
 if e=verify(req.Dest,req.Passphrase);e!=nil{return "",e}
 if e=writeExclusive(filepath.Join(req.Dest,"LOCAL_CAPTURE_VERIFIED.txt"),
  []byte("DAY12_P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED_ONLY - LOCAL ONLY. No upload. Not application consistent. Not a full backup."));e!=nil{return "",e}
 return h.ArchiveID,nil
}
func verify(dir,passphrase string) error {
 hb,e:=os.ReadFile(filepath.Join(dir,"header.json"))
 if e!=nil || len(hb)>4096{return fail("HEADER_UNAVAILABLE")}
 var h archiveHeader
 if e=json.Unmarshal(hb,&h);e!=nil{return fail("HEADER_INVALID")}
 a,e:=aeadFor(passphrase,h);if e!=nil{return e}
 mb,e:=os.ReadFile(filepath.Join(dir,"manifest.gcm"))
 if e!=nil || len(mb)>16384{return fail("MANIFEST_UNAVAILABLE")}
 plain,e:=decrypt(a,mb,[]byte("p0/manifest/v1/"+h.ArchiveID))
 if e!=nil{return e}
 var manifestObject manifest
 if e=json.Unmarshal(plain,&manifestObject);e!=nil{return fail("MANIFEST_PARSE_FAILED")}
 if manifestObject.Schema!=version || len(manifestObject.Files)!=len(requiredNames()){
  return fail("MANIFEST_REQUIRED_COUNT_MISMATCH")
 }
 required:=map[string]bool{};for _,name:=range requiredNames(){required[name]=true}
 encountered:=map[string]bool{}
 entries,e:=os.ReadDir(dir);if e!=nil{return fail("ARCHIVE_NOT_READABLE")}
 // Marker file is written after verify; a subsequent verify may contain it.
 expected:=len(required)+2
 if len(entries)!=expected && len(entries)!=expected+1{
  return fail("ARCHIVE_UNEXPECTED_PART_COUNT")
 }
 for i,r:=range manifestObject.Files {
  expectedPart:=fmt.Sprintf("part-%03d.gcm",i)
  if !safeName(r.Name) || !required[r.Name] || encountered[r.Name] ||
   r.Part!=expectedPart || r.Size<1 || r.Size>maximumOneFile {
   return fail("UNSAFE_MANIFEST_ENTRY")
  }
  encountered[r.Name]=true
  p:=filepath.Join(dir,r.Part)
  st,e:=os.Lstat(p)
  if e!=nil || !st.Mode().IsRegular() || st.Size()>maximumOneFile+1024{
   return fail("PART_MISSING_OR_UNSAFE")
  }
  b,e:=os.ReadFile(p);if e!=nil{return fail("PART_READ_FAILED")}
  restored,e:=decrypt(a,b,[]byte(fmt.Sprintf("p0/file/v1/%s/%d/%s",h.ArchiveID,i,r.Name)))
  if e!=nil || len(restored)!=r.Size || digest(restored)!=r.SHA256{
   return fail("RESTORE_AUTH_OR_HASH_MISMATCH")
  }
  clear(restored)
 }
 for _,entry:=range entries {
  n:=entry.Name()
  if n=="header.json" || n=="manifest.gcm" || n=="LOCAL_CAPTURE_VERIFIED.txt"{continue}
  if !strings.HasPrefix(n,"part-") || !strings.HasSuffix(n,".gcm"){
   return fail("UNEXPECTED_ARCHIVE_ENTRY")
  }
 }
 return nil
}
func fixture() error {
 root,e:=os.MkdirTemp("","day12-p0-local-fixture-");if e!=nil{return e}
 defer os.RemoveAll(root)
 local:=filepath.Join(root,"AppDataLocal")
 if e=os.Mkdir(local,0700);e!=nil{return e}
 oldEnv,hadEnv:=os.LookupEnv("LOCALAPPDATA")
 defer func(){if hadEnv{_ = os.Setenv("LOCALAPPDATA",oldEnv)}else{_ = os.Unsetenv("LOCALAPPDATA")}}()
 _=os.Setenv("LOCALAPPDATA",local)
 inputs:=filepath.Join(root,"inputs");if e=os.Mkdir(inputs,0700);e!=nil{return e}
 fixtures:=[]candidate{}
 for _,name:=range requiredNames(){
  p:=filepath.Join(inputs,fmt.Sprintf("input-%03d",len(fixtures)))
  body:=[]byte("SYNTHETIC_FAKE_CONFIG_OR_KEY:"+name+":NOT_REAL")
  if e=writeExclusive(p,body);e!=nil{return e}
  fixtures=append(fixtures,candidate{Name:name,Source:p})
 }
 // The fixture always uses strong fake credentials and a fixed private appdata.
 req:=request{Passphrase:"synthetic fixture string not for a real backup",
  Dest:filepath.Join(local,"Geumyi-P0-Encrypted-Staging","P0-FIXTURE-ABCDEFGHIJKLM"),Files:fixtures}
 _,e=addEncryptedFiles(req);if e!=nil{return e}
 if e=verify(req.Dest,req.Passphrase);e!=nil{return e}
 if e=verify(req.Dest,req.Passphrase+"wrong");e==nil{return fail("WRONG_PASSPHRASE_NOT_REJECTED")}
 // Real input never accepted from an unverified set.
 bad:=req;bad.Files=append([]candidate(nil),req.Files...)
 bad.Files[0].Name="paper/wild/world/region/r.0.0.mca"
 if _,e=checkInput(bad);e==nil{return fail("WORLD_FILE_NOT_BLOCKED")}
 bad=req;bad.Files=append([]candidate(nil),req.Files...)
 bad.Files[0].Name="../escape"
 if _,e=checkInput(bad);e==nil{return fail("TRAVERSAL_NOT_BLOCKED")}
 if _,e=checkInput(request{Passphrase:"short",Dest:req.Dest,Files:req.Files});e==nil{
  return fail("SHORT_PASSWORD_NOT_BLOCKED")
 }
 // Changing one ciphertext byte must fail verification.
 changed:=filepath.Join(req.Dest,"part-000.gcm")
 original,e:=os.ReadFile(changed);if e!=nil{return e}
 broken:=append([]byte(nil),original...);broken[len(broken)-1]^=0x80
 if e=os.WriteFile(changed,broken,0600);e!=nil{return e}
 if e=verify(req.Dest,req.Passphrase);e==nil{return fail("TAMPER_NOT_DETECTED")}
 if e=os.WriteFile(changed,original,0600);e!=nil{return e}
 if e=verify(req.Dest,req.Passphrase);e!=nil{return e}
 // No plain secret/config body appears in archive ciphertext.
 es,e:=os.ReadDir(req.Dest);if e!=nil{return e}
 for _,f:=range es {
  b,e:=os.ReadFile(filepath.Join(req.Dest,f.Name()));if e!=nil{return e}
  if bytes.Contains(b,[]byte("SYNTHETIC_FAKE_CONFIG_OR_KEY:")){
   return fail("PLAINTEXT_LEAK_TO_ARCHIVE")
  }
 }
 fmt.Printf("DAY12_P0_LOCAL_CAPTURE_DISPOSABLE_PASS exact_files=%d AES256GCM=true PBKDF2=true tamper_rejected=true no_cloud_upload=true no_operator_source_read=true
",len(req.Files))
 return nil
}
func main(){
 if len(os.Args)==2 && os.Args[1]=="--fixture" {
  if e:=fixture();e!=nil{fmt.Println("P0_SYNTHETIC_FIXTURE_FAILED:",e);os.Exit(3)}
  return
 }
 if len(os.Args)!=2 || os.Args[1]!="--capture"{
  fmt.Println("P0_REJECT_UNEXPECTED_ARGUMENTS")
  os.Exit(2)
 }
 requestBytes,e:=io.ReadAll(io.LimitReader(os.Stdin,64*1024+1))
 if e!=nil || len(requestBytes)>64*1024{fmt.Println("P0_PRIVATE_INPUT_INVALID");os.Exit(2)}
 var req request
 if e=json.Unmarshal(requestBytes,&req);e!=nil{
  fmt.Println("P0_PRIVATE_INPUT_INVALID");os.Exit(2)
 }
 id,e:=addEncryptedFiles(req)
 if e!=nil{
  // Never echo error paths, secret values, serialized request or source names.
  fmt.Println("P0_CAPTURE_BLOCKED_OR_INCOMPLETE:",e)
  os.Exit(2)
 }
 fmt.Println("P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED")
 fmt.Println("P0_CAPTURE_ID="+id)
 fmt.Println("P0_CLOUD_UPLOAD=false")
 fmt.Println("P0_FULL_RESTORE_VERIFIED=false")
 fmt.Println("P0_SOURCE_APPLICATION_CONSISTENCY=false")
 fmt.Println("P0_STABLE_RELEASE_ALLOWED=false")
 // No passphrase in output. Local staging path is printed by Windows wrapper.
 _=time.Now()
}
