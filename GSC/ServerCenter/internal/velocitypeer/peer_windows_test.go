//go:build windows

package velocitypeer

import (
    "os"
    "syscall"
    "testing"
)

func TestPinProcessGenerationQueryOnly(t *testing.T){
    p,err:=pinPID(uint32(os.Getpid()))
    if err!=nil{t.Fatalf("could not pin this CI runner's process: %v",err)}
    pid,born,err:=p.Reference()
    if err!=nil||pid!=uint32(os.Getpid())||born==0{t.Fatalf("invalid OS process reference")}
    if !p.SameGeneration(pid,born)||!p.StillAlive(){
        t.Fatal("kernel-owned live process handle not matched")
    }
    if p.SameGeneration(pid+1,born)||p.SameGeneration(pid,born+1)||
        p.SameGeneration(0,born)||p.SameGeneration(pid,0){
        t.Fatal("PID or generation mismatch was accepted")
    }
    if err:=p.Close();err!=nil{t.Fatalf("close failed: %v",err)}
    if p.StillAlive()||p.SameGeneration(pid,born){t.Fatal("closed proof used as active peer")}
    if _,_,err:=p.Reference();err==nil{t.Fatal("closed proof returned identity")}
    if err:=p.Close();err!=nil{t.Fatal("nonidempotent safe close")}
}

func TestWindowsPeerSIDRequiresPinnedExpectedPrincipal(t *testing.T) {
    token,err:=syscall.OpenCurrentProcessToken()
    if err!=nil{t.Fatalf("cannot query test process token: %v",err)}
    defer token.Close()
    u,err:=token.GetTokenUser()
    if err!=nil||u==nil||u.User.Sid==nil{t.Fatal("cannot read test token user SID")}
    sid,err:=u.User.Sid.String()
    if err!=nil||len(sid)<5{t.Fatal("empty OS token SID")}
    p,err:=pinPID(uint32(os.Getpid()))
    if err!=nil{t.Fatal(err)}
    if !p.SameWindowsPrincipal(sid){t.Fatal("matching kernel SID was not verified")}
    if p.SameWindowsPrincipal(sid+"-999")||p.SameWindowsPrincipal("")||
        p.SameWindowsPrincipal("S-1-0-0"){
        t.Fatal("arbitrary Windows account accepted")
    }
    if err:=p.Close();err!=nil{t.Fatal(err)}
    if p.SameWindowsPrincipal(sid){t.Fatal("closed process proof reused")}
}

func TestProtectedPipeDACLOnlyPinnedWindowsAccounts(t *testing.T){
    token,err:=syscall.OpenCurrentProcessToken()
    if err!=nil{t.Fatal(err)}
    defer token.Close()
    u,err:=token.GetTokenUser()
    if err!=nil||u.User.Sid==nil{t.Fatal("no current account SID")}
    sid,err:=u.User.Sid.String()
    if err!=nil{t.Fatal(err)}
    acl,err:=NewRestrictivePipeACL([]string{sid})
    if err!=nil{t.Fatalf("single-account DACL creation failed: %v",err)}
    if attr:=acl.Attributes();attr==nil||attr.SecurityDescriptor==0||attr.InheritHandle!=0{
        t.Fatal("native security attributes missing or inheritable")
    }
    if err:=acl.Close();err!=nil{t.Fatal(err)}
    if acl.Attributes()!=nil{t.Fatal("closed DACL reused")}
    if err:=acl.Close();err!=nil{t.Fatal("nonidempotent DACL close")}
    for _,tc:=range []struct{name string; sids []string}{
        {"none",nil},
        {"duplicates",[]string{sid,sid}},
        {"group-everyone",[]string{"S-1-1-0"}},
        {"group-authenticated-users",[]string{"S-1-5-11"}},
        {"group-administrators",[]string{"S-1-5-32-544"}},
        {"group-users",[]string{"S-1-5-32-545"}},
        {"anonymous",[]string{"S-1-5-7"}},
        {"malformed",[]string{"D:P(A;;GA;;;WD)"}},
        {"whitespace",[]string{" "+sid}},
        {"too-many",[]string{sid,"S-1-5-18","S-1-5-19"}},
    }{
        t.Run(tc.name,func(t *testing.T){
            acl,err:=NewRestrictivePipeACL(tc.sids)
            if err==nil{
                acl.Close()
                t.Fatal("unsafe/broad pipe allowlist accepted")
            }
        })
    }
}

func TestWindowsPipeClientProbeRejectsInvalidHandles(t *testing.T){
    for _,handle:=range []uintptr{0,^uintptr(0)}{
        p,err:=ObserveConnectedPipeClient(handle)
        if err==nil||p!=nil{t.Fatal("invalid pipe handle accepted")}
    }
    p,err:=ObserveConnectedPipeClient(12345)
    if err==nil||p!=nil{t.Fatal("unconnected pseudo handle accepted")}
}

func TestFailedProcessPinIsNotAttestation(t *testing.T){
    if p,err:=pinPID(0);err==nil||p!=nil{t.Fatal("zero PID accepted")}
    var empty *PeerObservation
    if empty.StillAlive()||empty.SameGeneration(1,1) {
        t.Fatal("nil peer proof accepted")
    }
    if _,_,err:=empty.Reference();err==nil{t.Fatal("nil peer exposed identity")}
    if err:=empty.Close();err!=nil{t.Fatal("nil close failed")}
}
