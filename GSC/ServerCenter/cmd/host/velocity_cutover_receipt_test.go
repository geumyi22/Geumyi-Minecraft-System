package main

import (
 "encoding/json"
 "os"
 "path/filepath"
 "strings"
 "testing"
)

func receiptFixtureFiles(t *testing.T) (string,string,string) {
 t.Helper()
 base:=t.TempDir()
 dir:=filepath.Join(base,"GeumyiServerCenter","VelocityManaged","Recovery")
 if err:=os.MkdirAll(dir,0700);err!=nil{t.Fatal(err)}
 original:=`<?xml version="1.0"?><Task><Settings><RestartOnFailure><Count>999</Count></RestartOnFailure></Settings></Task>`
 receipt:=velocityCutoverReceipt{
   Schema:1,Target:"wild",Ticket:"GSC-TEST-0001",
   OriginalSHA256:unicodeSHA256(original),
   OriginalTaskState:"Running",CutoverCommitted:true,
   CreatedUTC:"2026-10-19T00:00:00Z",
 }
 raw,err:=json.Marshal(receipt);if err!=nil{t.Fatal(err)}
 xmlPath:=filepath.Join(dir,"wild.original.xml")
 receiptPath:=filepath.Join(dir,"wild.receipt.json")
 if err:=os.WriteFile(xmlPath,[]byte(original),0600);err!=nil{t.Fatal(err)}
 if err:=os.WriteFile(receiptPath,raw,0600);err!=nil{t.Fatal(err)}
 return base,xmlPath,receiptPath
}

func TestMigrationReceiptRequiresOriginalSnapshotIntegrity(t *testing.T){
 base,_,_:=receiptFixtureFiles(t)
 ok,err:=loadVelocityCutoverReceipt("wild",base)
 if err!=nil||!ok{t.Fatalf("valid private synthetic snapshot rejected: %v",err)}
 for _,other:=range []string{"other","playground","../wild",""}{
  if ok,err:=loadVelocityCutoverReceipt(other,base);err==nil||ok{
   t.Fatalf("wrong target accepted: %s",other)
  }
 }
}

func TestMigrationReceiptInvalidationAndTampering(t *testing.T){
 modify:=[]struct{name string;f func(t *testing.T,xml,receipt string)}{
  {"missing-original",func(t *testing.T,xml,receipt string){_ = os.Remove(xml)}},
  {"missing-receipt",func(t *testing.T,xml,receipt string){_ = os.Remove(receipt)}},
  {"tampered-xml",func(t *testing.T,xml,receipt string){
    if err:=os.WriteFile(xml,[]byte("fake XML"),0600);err!=nil{t.Fatal(err)}
  }},
  {"approval-uncommitted",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["cutover_committed"]=false})
  }},
  {"invalid-ticket",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["ticket"]="../../secret"})
  }},
  {"unknown-field",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["os_sid"]="admin"})
  }},
  {"wrong-target",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["target"]="other"})
  }},
  {"bad-sha",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["original_sha256"]=strings.Repeat("0",64)})
  }},
  {"bad-original-state",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["original_task_state"]="Disabled"})
  }},
  {"bad-schema",func(t *testing.T,xml,receipt string){
    changeReceipt(t,receipt,func(m map[string]any){m["schema"]=2})
  }},
  {"duplicated-key",func(t *testing.T,xml,receipt string){
    original,err:=os.ReadFile(receipt);if err!=nil{t.Fatal(err)}
    s:=strings.TrimSuffix(string(original),"}")+`,"cutover_committed":true}`
    if err:=os.WriteFile(receipt,[]byte(s),0600);err!=nil{t.Fatal(err)}
  }},
  {"trailing-json",func(t *testing.T,xml,receipt string){
    orig,err:=os.ReadFile(receipt);if err!=nil{t.Fatal(err)}
    if err:=os.WriteFile(receipt,append(orig,[]byte("{}")...),0600);err!=nil{t.Fatal(err)}
  }},
 }
 for _,tc:=range modify{
  t.Run(tc.name,func(t *testing.T){
    base,xml,receipt:=receiptFixtureFiles(t)
    tc.f(t,xml,receipt)
    ok,err:=loadVelocityCutoverReceipt("wild",base)
    if err==nil||ok{t.Fatal("unsafe or tampered cutover receipt accepted")}
  })
 }
}

func changeReceipt(t *testing.T,path string,change func(map[string]any)){
 t.Helper()
 var data map[string]any
 raw,err:=os.ReadFile(path)
 if err!=nil{t.Fatal(err)}
 if err:=json.Unmarshal(raw,&data);err!=nil{t.Fatal(err)}
 change(data)
 out,err:=json.Marshal(data)
 if err!=nil{t.Fatal(err)}
 if err:=os.WriteFile(path,out,0600);err!=nil{t.Fatal(err)}
}
