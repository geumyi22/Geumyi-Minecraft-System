//go:build windows

package velocitypeer

import (
    "os"
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
