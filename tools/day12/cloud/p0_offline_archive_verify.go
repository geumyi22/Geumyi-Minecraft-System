//go:build ignore

// Independent P0 archive validator. NEVER contacts cloud, opens live servers,
// extracts plaintext, changes the archive, or writes a new backup.
// Reads the existing 20-part encrypted archive from the local private staging
// directory, verifies AEAD and hashes in memory, and discards decrypted bytes.
package main

import (
 "crypto/aes"
 "crypto/cipher"
 "crypto/hmac"
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
)

const formatVersion=1
const pbkdfRounds=450000
const singleLimit=8*1024*1024
const totalLimit=48*1024*1024
const fileCount=20

type privateRequest struct {
 Archive string `json:"archive"`
 Passphrase string `json:"passphrase"`
}
type header struct {
 Schema int `json:"schema"`
 KDF string `json:"kdf"`
 Iterations int `json:"iterations"`
 Salt string `json:"salt"`
 ArchiveID string `json:"archive_id"`
}
type part struct {
 Name string `json:"name"`
 Part string `json:"part"`
 Size int `json:"size"`
 SHA256 string `json:"sha256"`
}
type manifest struct {
 Schema int `json:"schema"`
 Files []part `json:"files"`
}
func reject(code string) error {return errors.New(code)}
func hash(b []byte) string{s:=sha256.Sum256(b);return hex.EncodeToString(s[:])}
func pbkdf2(password,salt []byte,iter,size int) []byte {
 output:=make([]byte,0,size)
 for block:=uint32(1);len(output)<size;block++{
  mac:=hmac.New(sha256.New,password)
  _,_=mac.Write(salt)
  _,_=mac.Write([]byte{byte(block>>24),byte(block>>16),byte(block>>8),byte(block)})
  u:=mac.Sum(nil);t:=append([]byte(nil),u...)
  for j:=1;j<iter;j++{
   mac=hmac.New(sha256.New,password);_,_=mac.Write(u)
   u=mac.Sum(nil)
   for k:=0;k<32;k++{t[k]^=u[k]}
  }
  output=append(output,t...)
 }
 return output[:size]
}
func expectedNames() []string {
 names:=[]string{"gsc/server.json"}
 for _,r:=range []string{"wild","playground","other","lobby"} {
  names=append(names,"paper/"+r+"/server.properties")
 }
 for _,r:=range []string{"wild","playground","other"}{
  for _,p:=range []string{"velocity.toml","forwarding.secret",
   "plugins/Geyser-Velocity/config.yml","plugins/floodgate/config.yml",
   "plugins/floodgate/key.pem"}{
    names=append(names,"proxy/"+r+"/"+p)
  }
 }
 sort.Strings(names)
 return names
}
func readRegular(dir,name string,max int64)([]byte,error){
 if name=="" || filepath.Base(name)!=name{return nil,reject("UNSAFE_ARCHIVE_NAME")}
 path:=filepath.Join(dir,name)
 info,err:=os.Lstat(path)
 if err!=nil || !info.Mode().IsRegular() || info.Size()<1 || info.Size()>max {
  return nil,reject("ARCHIVE_ENTRY_MISSING_UNSAFE_OR_OVERSIZED")
 }
 fd,err:=os.Open(path)
 if err!=nil{return nil,reject("ARCHIVE_ENTRY_READ_DENIED")}
 b,readErr:=io.ReadAll(io.LimitReader(fd,max+1))
 closeErr:=fd.Close()
 if readErr!=nil || closeErr!=nil || len(b)<1 || int64(len(b))>max ||
  int64(len(b))!=info.Size(){return nil,reject("ARCHIVE_ENTRY_READ_INCOMPLETE")}
 return b,nil
}
func validateArchivePath(directory string) error {
 local:=os.Getenv("LOCALAPPDATA")
 if local=="" || !filepath.IsAbs(local) || !filepath.IsAbs(directory){
  return reject("LOCAL_PRIVATE_ARCHIVE_ONLY")
 }
 actual,err:=filepath.Abs(filepath.Clean(directory))
 if err!=nil{return reject("ARCHIVE_PATH_INVALID")}
 expected:=filepath.Join(filepath.Clean(local),"Geumyi-P0-Encrypted-Staging")
 if !strings.EqualFold(filepath.Dir(actual),expected) ||
  !strings.HasPrefix(filepath.Base(actual),"P0-") ||
  len(filepath.Base(actual))<20{
  return reject("ARCHIVE_OUTSIDE_VERIFIED_PRIVATE_STAGING")
 }
 // Check known ancestors, no filesystem traversal or provider sync folders.
 for _,path:=range []string{filepath.Clean(local),expected,actual}{
  info,err:=os.Lstat(path)
  if err!=nil || !info.IsDir() || info.Mode()&os.ModeSymlink!=0{
   return reject("ARCHIVE_DIRECTORY_UNSAFE_OR_MISSING")
  }
 }
 return nil
}
func decrypt(aead cipher.AEAD,data,aad []byte)([]byte,error){
 if len(data)<aead.NonceSize()+aead.Overhead(){return nil,reject("CIPHERTEXT_TRUNCATED")}
 cleartext,err:=aead.Open(nil,data[:aead.NonceSize()],data[aead.NonceSize():],aad)
 if err!=nil{return nil,reject("AEAD_AUTHENTICATION_FAILED")}
 return cleartext,nil
}
func verifyArchive(req privateRequest) error {
 if len([]rune(req.Passphrase))<20 || len([]rune(req.Passphrase))>256 {
  return reject("PASSPHRASE_LENGTH_INVALID")
 }
 if err:=validateArchivePath(req.Archive);err!=nil{return err}
 expected:=expectedNames()
 if len(expected)!=fileCount{return reject("PROGRAMMER_FILE_COUNT_INCORRECT")}
 list,err:=os.ReadDir(req.Archive)
 if err!=nil || len(list)!=fileCount+3{return reject("ARCHIVE_MISSING_OR_UNEXPECTED_ENTRY")}
 allowed:=map[string]bool{"header.json":true,"manifest.gcm":true,"LOCAL_CAPTURE_VERIFIED.txt":true}
 for i:=0;i<fileCount;i++{allowed[fmt.Sprintf("part-%03d.gcm",i)]=true}
 for _,entry:=range list{
  name:=entry.Name()
  if !allowed[name]{return reject("ARCHIVE_UNEXPECTED_ENTRY")}
  info,err:=entry.Info()
  if err!=nil || !info.Mode().IsRegular(){return reject("ARCHIVE_NONREGULAR_ENTRY")}
 }
 marker,err:=readRegular(req.Archive,"LOCAL_CAPTURE_VERIFIED.txt",512)
 if err!=nil || !strings.HasPrefix(string(marker),"DAY12_P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED_ONLY"){
  return reject("CAPTURE_MARKER_INVALID")
 }
 hb,err:=readRegular(req.Archive,"header.json",4096)
 if err!=nil{return err}
 var h header
 if err=json.Unmarshal(hb,&h);err!=nil ||
  h.Schema!=formatVersion || h.KDF!="PBKDF2-HMAC-SHA256" ||
  h.Iterations!=pbkdfRounds || len(h.ArchiveID)!=32{
  return reject("HEADER_UNSUPPORTED")
 }
 id,err:=hex.DecodeString(h.ArchiveID)
 if err!=nil || len(id)!=16{return reject("ARCHIVE_ID_INVALID")}
 salt,err:=base64.RawStdEncoding.DecodeString(h.Salt)
 if err!=nil || len(salt)!=24{return reject("ARCHIVE_SALT_INVALID")}
 key:=pbkdf2([]byte(req.Passphrase),salt,pbkdfRounds,32)
 defer clear(key)
 aesBlock,err:=aes.NewCipher(key);if err!=nil{return reject("CIPHER_INIT_FAILED")}
 aead,err:=cipher.NewGCM(aesBlock);if err!=nil{return reject("AEAD_INIT_FAILED")}
 encryptedManifest,err:=readRegular(req.Archive,"manifest.gcm",16384)
 if err!=nil{return err}
 manifestBytes,err:=decrypt(aead,encryptedManifest,[]byte("p0/manifest/v1/"+h.ArchiveID))
 if err!=nil{return err}
 var m manifest
 if err=json.Unmarshal(manifestBytes,&m);err!=nil ||
  m.Schema!=formatVersion || len(m.Files)!=fileCount{
  return reject("ENCRYPTED_MANIFEST_INVALID")
 }
 total:=0
 keyHashes:=map[string]string{}
 for i,p:=range m.Files{
  name:=expected[i]
  partName:=fmt.Sprintf("part-%03d.gcm",i)
  if p.Name!=name || p.Part!=partName || p.Size<1 || p.Size>singleLimit ||
     len(p.SHA256)!=64{
   return reject("MANIFEST_EXACT_FILE_CONTRACT_FAILED")
  }
  if _,err=hex.DecodeString(p.SHA256);err!=nil{
   return reject("MANIFEST_DIGEST_INVALID")
  }
  total+=p.Size
  if total>totalLimit{return reject("P0_TOTAL_SIZE_LIMIT_EXCEEDED")}
  blob,err:=readRegular(req.Archive,partName,int64(singleLimit+1024))
  if err!=nil{return err}
  clearBytes,err:=decrypt(aead,blob,[]byte(fmt.Sprintf(
   "p0/file/v1/%s/%d/%s",h.ArchiveID,i,name)))
  if err!=nil{return err}
  if len(clearBytes)!=p.Size || hash(clearBytes)!=p.SHA256{
   clear(clearBytes)
   return reject("PART_SIZE_OR_SHA256_MISMATCH")
  }
  if strings.HasSuffix(name,"/forwarding.secret") ||
     strings.HasSuffix(name,"/plugins/floodgate/key.pem"){
   keyGroup:="forwarding"
   if strings.HasSuffix(name,"/key.pem"){keyGroup="floodgate"}
   current:=hash(clearBytes)
   if original,ok:=keyHashes[keyGroup];ok && current!=original{
    clear(clearBytes)
    return reject("CAPTURED_THREE_PROXY_KEYS_DIFFER")
   }
   keyHashes[keyGroup]=current
  }
  clear(clearBytes)
 }
 if len(keyHashes)!=2{return reject("PROXY_KEY_PAIR_INCOMPLETE")}
 return nil
}
func main() {
 if len(os.Args)!=2 || os.Args[1]!="--verify"{
  fmt.Println("P0_OFFLINE_VERIFY_ARGUMENTS_REFUSED");os.Exit(2)
 }
 data,err:=io.ReadAll(io.LimitReader(os.Stdin,32*1024+1))
 if err!=nil || len(data)>32*1024 {fmt.Println("P0_OFFLINE_PRIVATE_INPUT_INVALID");os.Exit(2)}
 var req privateRequest
 if err=json.Unmarshal(data,&req);err!=nil{
  fmt.Println("P0_OFFLINE_PRIVATE_INPUT_INVALID");os.Exit(2)
 }
 clear(data)
 err=verifyArchive(req)
 if err!=nil{
  fmt.Println("P0_OFFLINE_VERIFY_BLOCKED:",err)
  fmt.Println("P0_CLOUD_UPLOAD_NOT_YET_VERIFIED")
  os.Exit(2)
 }
 fmt.Println("P0_OFFLINE_VERIFY_PASS")
 fmt.Println("P0_ENCRYPTED_FILES_VERIFIED=20")
 fmt.Println("P0_PLAINTEXT_FILES_WRITTEN=false")
 fmt.Println("P0_CLOUD_UPLOAD_NOT_YET_VERIFIED")
 fmt.Println("P0_APPLICATION_RESTORE_NOT_VERIFIED")
 fmt.Println("P0_STABLE_RELEASE_ALLOWED=false")
}
