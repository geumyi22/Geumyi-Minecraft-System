//go:build windows

package velocitypeer

import (
    "errors"
    "strings"
    "sync"
    "syscall"
    "unsafe"
)

// RestrictivePipeACL constructs a DACL in native memory but creates NO pipe,
// socket, service, process, task, or OS ACL modification. The future broker
// must pass Attributes() into its own guarded CreateNamedPipeW call.
type RestrictivePipeACL struct {
    mu sync.Mutex
    descriptor uintptr
    attrs syscall.SecurityAttributes
}

var advapi32Pipe=syscall.NewLazyDLL("advapi32.dll")
var convertSDDL=advapi32Pipe.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
var errPipeACL=errors.New("named-pipe allowlist security descriptor rejected")

// NewRestrictivePipeACL permits exactly one or two individually pinned
// Windows account SIDs (typically the GSC broker and the Velocity JVM service
// account). NO Everyone, Authenticated Users, default permissive DACL,
// administrator bypass or anonymous access is added. Users that share an
// allowed SID can still connect: challenge/HMAC and process-generation
// checks are mandatory separate defenses.
func NewRestrictivePipeACL(allowed []string) (*RestrictivePipeACL,error){
    if len(allowed)<1 || len(allowed)>2{return nil,errPipeACL}
    seen:=map[string]bool{}
    var ace strings.Builder
    ace.WriteString("D:P")
    for _,value:=range allowed{
        if len(value)<7 || len(value)>184 || value!=strings.TrimSpace(value){
            return nil,errPipeACL
        }
        sid,err:=syscall.StringToSid(value)
        if err!=nil||sid==nil{return nil,errPipeACL}
        canonical,err:=sid.String()
        if err!=nil || canonical!=value || seen[value]{return nil,errPipeACL}
        seen[value]=true
        ace.WriteString("(A;;GA;;;")
        ace.WriteString(value)
        ace.WriteString(")")
    }
    p,err:=syscall.UTF16PtrFromString(ace.String())
    if err!=nil{return nil,errPipeACL}
    var descriptor uintptr
    ret,_,_:=convertSDDL.Call(uintptr(unsafe.Pointer(p)),1,
        uintptr(unsafe.Pointer(&descriptor)),0)
    if ret==0||descriptor==0{return nil,errPipeACL}
    a:=&RestrictivePipeACL{descriptor:descriptor}
    a.attrs=syscall.SecurityAttributes{
        Length:uint32(unsafe.Sizeof(syscall.SecurityAttributes{})),
        SecurityDescriptor:descriptor,
        InheritHandle:0,
    }
    return a,nil
}

// Attributes returns native memory valid only while this object remains open.
// Never retain this pointer after Close. Use only for CreateNamedPipeW.
func (a *RestrictivePipeACL) Attributes() *syscall.SecurityAttributes{
    if a==nil{return nil}
    a.mu.Lock()
    defer a.mu.Unlock()
    if a.descriptor==0{return nil}
    return &a.attrs
}

func (a *RestrictivePipeACL) Close() error{
    if a==nil{return nil}
    a.mu.Lock()
    defer a.mu.Unlock()
    if a.descriptor==0{return nil}
    descriptor:=a.descriptor
    a.descriptor=0
    a.attrs.SecurityDescriptor=0
    _,err:=syscall.LocalFree(syscall.Handle(descriptor))
    if err!=nil{return errPipeACL}
    return nil
}
