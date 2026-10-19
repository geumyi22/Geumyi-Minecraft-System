package main

import (
 "os"
 "path/filepath"
 "testing"
)

func ownedMarkerFixture(t *testing.T)(string,string){
 t.Helper()
 root:=t.TempDir()
 folder:=filepath.Join(root,"GeumyiServerCenter","VelocityManaged","Recovery")
 if err:=os.MkdirAll(folder,0700);err!=nil{t.Fatal(err)}
 return root,folder
}
func TestVelocityOwnerGenerationSurvivesHostCrashAndBlocksDuplicates(t *testing.T){
 root,folder:=ownedMarkerFixture(t)
 one,err:=createOwnedMarker("wild",root)
 if err!=nil{t.Fatal(err)}
 if len(one)!=48{t.Fatal("generation entropy/encoding unexpected")}
 if !ownedMarkerPresent("wild",root){t.Fatal("owner marker absent after start")}
 if _,err:=createOwnedMarker("wild",root);err==nil{
  t.Fatal("host restart could silently launch a duplicate Java generation")
 }
 if _,err:=createOwnedMarker("other",root);err!=nil{t.Fatal("different proxy generation rejected",err)}
 if err:=releaseOwnedMarker("wild",root,"000000000000000000000000000000000000000000000000");err==nil{
  t.Fatal("old host generation removed newer owner marker")
 }
 if err:=releaseOwnedMarker("wild",root,one);err!=nil{t.Fatal(err)}
 if ownedMarkerPresent("wild",root){t.Fatal("confirmed owner release still blocked")}
 if _,err:=createOwnedMarker("wild",root);err!=nil{t.Fatal("clean confirmed exit cannot launch next generation",err)}
 if err:=os.Remove(filepath.Join(folder,"wild.active.json"));err!=nil{t.Fatal(err)}
}
func TestVelocityOwnerMarkerFailsClosedWhenArchiveMissing(t *testing.T){
 root:=t.TempDir()
 if _,err:=createOwnedMarker("wild",root);err==nil{
  t.Fatal("unprotected or uninitialized cutover archive accepted")
 }
 if !ownedMarkerPresent("wild",root){
  t.Fatal("unavailable original archive treated as cleared owner generation")
 }
 if _,err:=createOwnedMarker("../wild",root);err==nil{
  t.Fatal("invalid marker target accepted")
 }
}
func TestVelocityOwnerMarkerTamperingBlocksReuse(t *testing.T){
 root,folder:=ownedMarkerFixture(t)
 nonce,err:=createOwnedMarker("wild",root)
 if err!=nil{t.Fatal(err)}
 p:=filepath.Join(folder,"wild.active.json")
 if err:=os.WriteFile(p,[]byte("{\"schema\":1,\"target\":\"wild\",\"generation\":\"bad\"}"),0600);err!=nil{t.Fatal(err)}
 if err:=releaseOwnedMarker("wild",root,nonce);err==nil{
  t.Fatal("malformed owner record allowed delete")
 }
 if !ownedMarkerPresent("wild",root){t.Fatal("malformed marker was incorrectly deleted")}
}
