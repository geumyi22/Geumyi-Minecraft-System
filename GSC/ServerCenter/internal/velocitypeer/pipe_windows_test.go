//go:build windows

package velocitypeer

import (
    "crypto/rand"
    "encoding/hex"
    "errors"
    "os"
    "syscall"
    "testing"
    "time"
    "unsafe"
)

var (
    createNamedPipeW=syscall.NewLazyDLL("kernel32.dll").NewProc("CreateNamedPipeW")
    connectNamedPipe=syscall.NewLazyDLL("kernel32.dll").NewProc("ConnectNamedPipe")
)

const (
    pipeAccessDuplex=0x00000003
    pipeRejectRemoteClients=0x00000008
    pipeOpenMaxInstances=1
    pipeConnectedError=syscall.Errno(535)
)

// CI-only real OS named-pipe handshake. The fixture creates NO listener used
// by GSC, Velocity, players, or a server task; both endpoints are within this
// test process and all handles are closed. No shutdown or task API exists.
func TestWindowsConnectedPipeReportsKernelClientGeneration(t *testing.T){
    var id [10]byte
    if _,err:=rand.Read(id[:]);err!=nil{t.Fatal(err)}
    name:=\`\\.\pipe\GSC452-CI-PEER-\`+hex.EncodeToString(id[:])
    namep,err:=syscall.UTF16PtrFromString(name)
    if err!=nil{t.Fatal(err)}
    server,_,callerr:=createNamedPipeW.Call(uintptr(unsafe.Pointer(namep)),
        pipeAccessDuplex,pipeRejectRemoteClients,pipeOpenMaxInstances,4096,4096,0,0)
    if server==0||server==uintptr(syscall.InvalidHandle){
        t.Fatalf("CI named pipe creation failed: %v",callerr)
    }
    defer closeHandle.Call(server)

    connected:=make(chan error,1)
    go func(){
        r,_,e:=connectNamedPipe.Call(server,0)
        if r==0&&!errors.Is(e,pipeConnectedError){
            connected<-errors.New("test named pipe not connected")
            return
        }
        connected<-nil
    }()
    var client syscall.Handle
    deadline:=time.Now().Add(3*time.Second)
    for time.Now().Before(deadline){
        client,err=syscall.CreateFile(namep,
            syscall.GENERIC_READ|syscall.GENERIC_WRITE,0,nil,syscall.OPEN_EXISTING,0,0)
        if err==nil{break}
        time.Sleep(20*time.Millisecond)
    }
    if err!=nil{
        t.Fatalf("CI-owned pipe client failed to connect: %v",err)
    }
    defer syscall.CloseHandle(client)
    select {
    case err:=<-connected:
        if err!=nil{t.Fatal(err)}
    case <-time.After(5*time.Second):
        t.Fatal("CI test pipe connect did not finish")
    }

    observed,err:=ObserveConnectedPipeClient(server)
    if err!=nil{t.Fatalf("OS client PID/creation probe failed: %v",err)}
    defer observed.Close()
    pid,born,err:=observed.Reference()
    if err!=nil||pid!=uint32(os.Getpid())||born==0||
        !observed.SameGeneration(pid,born)||!observed.StillAlive(){
        t.Fatal("OS-reported client process generation was not pinned")
    }
    if observed.SameGeneration(pid,born+1){
        t.Fatal("PID-only process substitution was accepted")
    }
}
