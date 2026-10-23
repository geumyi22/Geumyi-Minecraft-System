//go:build windows

package velocitybridge

import (
    "bytes"
    "strings"
    "testing"
)

func TestWindowsUserDPAPIProxyKeysAreScopedAndNeverPlaintext(t *testing.T){
    saved:=map[string]string{}
    for _,target:=range []string{"wild","playground","other"} {
        ciphertext,err:=GenerateUserProtectedProxyKey(target)
        if err!=nil{t.Fatalf("%s DPAPI encryption unavailable: %v",target,err)}
        if !strings.HasPrefix(ciphertext,"dpapi-u:")||
            strings.Contains(ciphertext,protectedKeyPrefix)||
            len(ciphertext)>8192 {
            t.Fatalf("%s plaintext/unbounded DPAPI output",target)
        }
        saved[target]=ciphertext
        key,err:=OpenUserProtectedProxyKey(target,ciphertext)
        if err!=nil||len(key)!=32{t.Fatalf("%s DPAPI key roundtrip failed: %v",target,err)}
        verifier,err:=NewChallengeVerifier(key)
        if err!=nil{t.Fatal(err)}
        c,err:=verifier.Issue(target,"status","generation-ci-only-12345",challengeTime)
        if err!=nil{t.Fatal(err)}
        signed,err:=SignChallenge(key,c)
        if err!=nil{t.Fatal(err)}
        if err:=verifier.VerifyIssuedOnce(signed,target,"status","generation-ci-only-12345",challengeTime);err!=nil{
            t.Fatalf("%s DPAPI-protected key could not verify one-time challenge: %v",target,err)
        }
        for i:=range key{key[i]=0}
    }
    if saved["wild"]==saved["other"]||saved["wild"]==saved["playground"]{
        t.Fatal("different proxy DPAPI keys collided")
    }
    if _,err:=OpenUserProtectedProxyKey("wild",saved["other"]);err==nil{
        t.Fatal("cross-proxy protected key substitution accepted")
    }
    if _,err:=OpenUserProtectedProxyKey("wild",saved["playground"]);err==nil{
        t.Fatal("cross-proxy alias accepted")
    }
}

func TestWindowsDPAPIKeyDecoderFailClosed(t *testing.T){
    sample,err:=GenerateUserProtectedProxyKey("wild")
    if err!=nil{t.Fatal(err)}
    tests:=[]struct{name,target,blob string}{
        {"unknown-target","lobby",sample},
        {"plain-key","wild",strings.Repeat("Z",32)},
        {"plaintext-shaped","wild",protectedKeyPrefix+"wild:"+strings.Repeat("A",43)},
        {"machine-scope","wild","dpapi-m:"+strings.TrimPrefix(sample,"dpapi-u:")},
        {"missing-value","wild",""},
        {"malformed-base64","wild","dpapi-u:@@@"},
        {"truncated-blob","wild",sample[:len(sample)-8]},
        {"wrong-target","other",sample},
        {"oversized","wild","dpapi-u:"+strings.Repeat("A",9000)},
    }
    for _,tc:=range tests{
        t.Run(tc.name,func(t *testing.T){
            key,err:=OpenUserProtectedProxyKey(tc.target,tc.blob)
            if err==nil||!bytes.Equal(key,nil){
                t.Fatal("untrusted plaintext/machine/corrupted key accepted")
            }
        })
    }
    if key,err:=GenerateUserProtectedProxyKey("lobby");err==nil||key!=""{
        t.Fatal("invalid target generated a secret")
    }
}
