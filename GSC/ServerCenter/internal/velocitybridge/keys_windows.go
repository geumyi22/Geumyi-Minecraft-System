//go:build windows

package velocitybridge

import (
    "crypto/rand"
    "encoding/base64"
    "errors"
    "strings"

    "geumyi/servercenter/internal/securestore"
)

var errSecretRejected=errors.New("velocity per-proxy key material rejected")
const protectedKeyPrefix="geumyi-velocity-hmac-v1:"

// GenerateUserProtectedProxyKey generates one random 256-bit HMAC key for
// ONE proxy, seals it using Windows CURRENT-USER DPAPI, and returns only the
// opaque ciphertext. It does not save a file or update any host configuration.
// A future approved installer must apply restrictive NTFS ACLs and keep the
// server and plugin accounts consistent before any live use.
func GenerateUserProtectedProxyKey(target string) (string,error){
    if !allowedTarget(target){return "",errSecretRejected}
    key:=make([]byte,32)
    if _,err:=rand.Read(key);err!=nil{return "",errSecretRejected}
    defer func(){for i:=range key{key[i]=0}}()
    plaintext:=protectedKeyPrefix+target+":"+base64.RawStdEncoding.EncodeToString(key)
    ciphertext,err:=securestore.ProtectString(plaintext,false)
    if err!=nil||!strings.HasPrefix(ciphertext,"dpapi-u:"){
        return "",errSecretRejected
    }
    return ciphertext,nil
}

// OpenUserProtectedProxyKey REQUIRES a dpapi-u: blob. The existing general
// securestore.UnprotectString supports legacy plaintext; this wrapper
// DELIBERATELY refuses plaintext, machine-scope dpapi-m, wrong target and
// malformed/untrusted key shapes. Caller must avoid printing keys.
func OpenUserProtectedProxyKey(target,protected string) ([]byte,error){
    if !allowedTarget(target)||len(protected)<16||len(protected)>8192||
        !strings.HasPrefix(protected,"dpapi-u:"){return nil,errSecretRejected}
    plaintext,err:=securestore.UnprotectString(protected)
    if err!=nil{return nil,errSecretRejected}
    head:=protectedKeyPrefix+target+":"
    if !strings.HasPrefix(plaintext,head){return nil,errSecretRejected}
    encoded:=strings.TrimPrefix(plaintext,head)
    if len(encoded)!=43{return nil,errSecretRejected}
    key,err:=base64.RawStdEncoding.DecodeString(encoded)
    if err!=nil||len(key)!=32{return nil,errSecretRejected}
    return key,nil
}
