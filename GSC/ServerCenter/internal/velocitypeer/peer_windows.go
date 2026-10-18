//go:build windows

// Package velocitypeer contains read-only, Windows OS-backed identity
// primitives for a FUTURE named-pipe transport. This package does not create
// or listen on pipes, change task policy, or start/stop any process.
// A PID/creation time IS NOT user authorization, correct task ownership,
// an authenticated Java plugin, or a safe-to-stop signal.
package velocitypeer

import (
    "errors"
    "sync"
    "syscall"
    "unsafe"
)

const processQueryLimitedInformation=0x1000
const stillActive=259

var (
    kernel32=syscall.NewLazyDLL("kernel32.dll")
    getNamedPipeClientProcessID=kernel32.NewProc("GetNamedPipeClientProcessId")
    openProcess=kernel32.NewProc("OpenProcess")
    closeHandle=kernel32.NewProc("CloseHandle")
    getProcessTimes=kernel32.NewProc("GetProcessTimes")
    getExitCodeProcess=kernel32.NewProc("GetExitCodeProcess")
)
var errUnverified=errors.New("Windows peer process generation not verified")

// PeerObservation holds a pinned OS process handle. Keeping it open prevents
// this Windows PID from being recycled until Close. The record is intentionally
// opaque to public JSON and grants no task/JVM operation.
type PeerObservation struct {
    mu sync.Mutex
    handle uintptr
    pid uint32
    born uint64
}

func filetimeStamp(f syscall.Filetime) uint64 {
    return uint64(f.HighDateTime)<<32|uint64(f.LowDateTime)
}

func pinPID(pid uint32) (*PeerObservation,error){
    if pid==0 {return nil,errUnverified}
    h,_,_:=openProcess.Call(processQueryLimitedInformation,0,uintptr(pid))
    if h==0 {return nil,errUnverified}
    ok:=false
    defer func(){if !ok{closeHandle.Call(h)}}()
    var created,exited,kernel,user syscall.Filetime
    r,_,_:=getProcessTimes.Call(h,
        uintptr(unsafe.Pointer(&created)),uintptr(unsafe.Pointer(&exited)),
        uintptr(unsafe.Pointer(&kernel)),uintptr(unsafe.Pointer(&user)))
    if r==0 || filetimeStamp(created)==0 {return nil,errUnverified}
    var exit uint32
    r,_,_ = getExitCodeProcess.Call(h,uintptr(unsafe.Pointer(&exit)))
    if r==0 || exit!=stillActive{return nil,errUnverified}
    ok=true
    return &PeerObservation{handle:h,pid:pid,born:filetimeStamp(created)},nil
}

// ObserveConnectedPipeClient accepts only a HANDLE that the future local
// broker created using CreateNamedPipe and connected successfully. Invalid or
// disconnected handles fail closed. It opens the kernel-reported CLIENT PID
// with query-only rights and verifies the PID again while holding the process
// handle (which pins PID reuse). It never executes a lifecycle action.
// Pipe DACLs, logon-token identity, process executable attestation and GSC
// operator approval are separate MANDATORY controls, not performed here.
func ObserveConnectedPipeClient(serverPipe uintptr) (*PeerObservation,error){
    if serverPipe==0 || serverPipe==^uintptr(0){return nil,errUnverified}
    var pid uint32
    r,_,_:=getNamedPipeClientProcessID.Call(serverPipe,uintptr(unsafe.Pointer(&pid)))
    if r==0||pid==0{return nil,errUnverified}
    proof,err:=pinPID(pid)
    if err!=nil{return nil,errUnverified}
    var later uint32
    r,_,_=getNamedPipeClientProcessID.Call(serverPipe,uintptr(unsafe.Pointer(&later)))
    if r==0 || later!=pid || later==0 || !proof.StillAlive(){
        _=proof.Close()
        return nil,errUnverified
    }
    return proof,nil
}

// SameGeneration checks caller-held expected kernel PID and creation FILETIME.
// It does not trust a PID alone, and never turns true into live authorization.
func (p *PeerObservation) SameGeneration(expectedPID uint32,expectedCreationFILETIME uint64) bool {
    if p==nil||expectedPID==0||expectedCreationFILETIME==0{return false}
    p.mu.Lock()
    defer p.mu.Unlock()
    return p.handle!=0&&p.pid==expectedPID&&p.born==expectedCreationFILETIME&&aliveHandle(p.handle)
}
func aliveHandle(h uintptr) bool{
    if h==0{return false}
    var exit uint32
    r,_,_:=getExitCodeProcess.Call(h,uintptr(unsafe.Pointer(&exit)))
    return r!=0&&exit==stillActive
}
func (p *PeerObservation) StillAlive() bool {
    if p==nil{return false}
    p.mu.Lock()
    defer p.mu.Unlock()
    return aliveHandle(p.handle)
}

// Reference is only an in-memory test/attestation comparison value. Do not
// serialize raw process identity into operator report files.
func (p *PeerObservation) Reference() (uint32,uint64,error){
    if p==nil{return 0,0,errUnverified}
    p.mu.Lock()
    defer p.mu.Unlock()
    if !aliveHandle(p.handle){return 0,0,errUnverified}
    return p.pid,p.born,nil
}
func (p *PeerObservation) Close() error {
    if p==nil{return nil}
    p.mu.Lock()
    defer p.mu.Unlock()
    if p.handle==0{return nil}
    h:=p.handle
    p.handle=0
    r,_,_:=closeHandle.Call(h)
    if r==0{return errUnverified}
    return nil
}
