//go:build windows

package velocitypeer

import (
    "crypto/rand"
    "encoding/hex"
    "errors"
    "fmt"
    "io"
    "os"
    "os/exec"
    "syscall"
    "testing"
    "time"
    "unsafe"

    "geumyi/servercenter/internal/velocitybridge"
)

// These are CI-only test-owned process and named-pipe operations. Production
// peer_windows.go contains NO listener, child-process launch or task command.
type testHandleIO struct{h syscall.Handle}
func (v testHandleIO) Read(p []byte)(int,error){
    var n uint32
    if err:=syscall.ReadFile(v.h,p,&n,nil);err!=nil{return int(n),err}
    return int(n),nil
}
func (v testHandleIO) Write(p []byte)(int,error){
    var n uint32
    if err:=syscall.WriteFile(v.h,p,&n,nil);err!=nil{return int(n),err}
    return int(n),nil
}
func onlyCIKey() []byte{return []byte("GSC452-CI-only-key-not-production!")}
func TestIPCChildProcessHelper(t *testing.T){
    if os.Getenv("GSC452_CI_PIPE_CHILD")!="1"{return}
    name:=os.Getenv("GSC452_CI_PIPE_NAME")
    if len(name)<28||len(name)>240{t.Fatal("invalid test-only pipe name")}
    ptr,err:=syscall.UTF16PtrFromString(name)
    if err!=nil{t.Fatal(err)}
    var client syscall.Handle
    for deadline:=time.Now().Add(8*time.Second);time.Now().Before(deadline);{
        client,err=syscall.CreateFile(ptr,syscall.GENERIC_READ|syscall.GENERIC_WRITE,0,nil,syscall.OPEN_EXISTING,0,0)
        if err==nil {break}
        time.Sleep(20*time.Millisecond)
    }
    if err!=nil {t.Fatalf("test-only client pipe connect failed: %v",err)}
    defer syscall.CloseHandle(client)
    ioPipe:=testHandleIO{client}
    challenge,err:=velocitybridge.UnmarshalChallengeFrame(ioPipe)
    if err!=nil{t.Fatalf("bad test challenge: %v",err)}
    response,err:=velocitybridge.SignChallenge(onlyCIKey(),challenge)
    if err!=nil{t.Fatal(err)}
    if err:=velocitybridge.MarshalSignedEnvelopeFrame(ioPipe,response);err!=nil{t.Fatal(err)}
    var ack [1]byte
    if _,err:=io.ReadFull(ioPipe,ack[:]);err!=nil||ack[0]!=1 {
        t.Fatalf("test-only parent did not acknowledge OS proof: %v",err)
    }
}
func TestWindowsDifferentProcessPipeAndSignedChallenge(t *testing.T){
    // No live Velocity, installed bridge, Windows task, ports or secrets.
    var id [12]byte
    if _,err:=rand.Read(id[:]);err!=nil{t.Fatal(err)}
    name:="\\\\.\\pipe\\GSC452-CI-CHALLENGE-"+hex.EncodeToString(id[:])
    namep,err:=syscall.UTF16PtrFromString(name)
    if err!=nil{t.Fatal(err)}
    raw,_,callerr:=createNamedPipeW.Call(uintptr(unsafe.Pointer(namep)),
        pipeAccessDuplex,pipeRejectRemoteClients,1,4096,4096,0,0)
    if raw==0||raw==uintptr(syscall.InvalidHandle){
        t.Fatalf("test pipe creation failed: %v",callerr)
    }
    defer closeHandle.Call(raw)
    cmd:=exec.Command(os.Args[0],"-test.run=^TestIPCChildProcessHelper$")
    cmd.Env=append(os.Environ(),"GSC452_CI_PIPE_CHILD=1","GSC452_CI_PIPE_NAME="+name)
    if err:=cmd.Start();err!=nil{t.Fatal(err)}
    processDone:=false
    defer func(){
        if !processDone{
            _=cmd.Process.Kill() // ONLY the test-owned child
            _=cmd.Wait()
        }
    }()
    connected:=make(chan error,1)
    go func(){
        ret,_,callerr:=connectNamedPipe.Call(raw,0)
        if ret==0&&!errors.Is(callerr,pipeConnectedError){
            connected<-fmt.Errorf("test-only ConnectNamedPipe failed: %v",callerr)
            return
        }
        connected<-nil
    }()
    select{
    case err:=<-connected:
        if err!=nil{t.Fatal(err)}
    case <-time.After(8*time.Second):
        t.Fatal("test-only pipe handshake timeout")
    }

    proof,err:=ObserveConnectedPipeClient(raw)
    if err!=nil{t.Fatalf("OS peer process identity not obtained: %v",err)}
    defer proof.Close()
    pid,born,err:=proof.Reference()
    if err!=nil||pid!=uint32(cmd.Process.Pid)||born==0||!proof.SameGeneration(pid,born){
        t.Fatal("kernel-assigned client PID/generation differed from child")
    }
    token,err:=syscall.OpenCurrentProcessToken()
    if err!=nil{t.Fatal(err)}
    user,err:=token.GetTokenUser()
    if err!=nil{token.Close();t.Fatal(err)}
    sid,err:=user.User.Sid.String()
    token.Close()
    if err!=nil||!proof.SameWindowsPrincipal(sid)||proof.SameWindowsPrincipal(sid+"-other"){
        t.Fatal("kernel account SID mismatch or forged SID accepted")
    }

    verifier,err:=velocitybridge.NewChallengeVerifier(onlyCIKey())
    if err!=nil{t.Fatal(err)}
    challenge,err:=verifier.Issue("playground","status","generation-ci-only-12345",time.Now())
    if err!=nil{t.Fatal(err)}
    stream:=testHandleIO{syscall.Handle(raw)}
    if err:=velocitybridge.MarshalChallengeFrame(stream,challenge);err!=nil{t.Fatal(err)}
    response,err:=velocitybridge.UnmarshalSignedEnvelopeFrame(stream)
    if err!=nil{t.Fatal(err)}
    if err:=verifier.VerifyIssuedOnce(response,"playground","status","generation-ci-only-12345",time.Now());err!=nil{
        t.Fatalf("OS-connected challenge response rejected: %v",err)
    }
    restarted,_:=velocitybridge.NewChallengeVerifier(onlyCIKey())
    if restarted.VerifyIssuedOnce(response,response.Target,response.Operation,response.Generation,time.Now())==nil{
        t.Fatal("replayed signed response accepted by fresh receiver")
    }
    if _,err:=stream.Write([]byte{1});err!=nil{t.Fatal(err)}
    childWait:=make(chan error,1)
    go func(){childWait<-cmd.Wait()}()
    select{
    case err:=<-childWait:
        processDone=true
        if err!=nil{t.Fatalf("test-owned Java proxy substitute failed: %v",err)}
    case <-time.After(8*time.Second):
        t.Fatal("test-only child did not exit after authenticated reply")
    }
}
