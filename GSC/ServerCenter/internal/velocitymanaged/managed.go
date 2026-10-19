// Package velocitymanaged provides a genuine process-ownership engine for
// a FUTURE GSC-owned Velocity runtime. It controls ONLY processes it starts.
// Unlike Task Scheduler PID guesses, no adopted/foreign JVM may be signalled.
//
// IMPORTANT: source-only, not connected to GSC host routes or Windows tasks.
// Transition requires a separate approved cutover and a verified Java launcher.
// There is no force-kill fallback or automatic task-policy mutation.
package velocitymanaged

import (
 "context"
 "errors"
 "io"
 "os/exec"
 "path/filepath"
 "sync"
)

var (
 ErrBusy=errors.New("managed Velocity process already running or changing")
 ErrNotOwned=errors.New("no GSC-owned Velocity process")
 ErrPermit=errors.New("verified player maintenance and task migration required")
 ErrShutdownTimeout=errors.New("graceful shutdown unconfirmed; process remains under observation")
)

type Spec struct {
 Target string
 Executable string
 Args []string
 WorkingDirectory string
 // Optional private host-owned log sink; never serialize it into API status.
 // Callers must cap/redact persisted output and protect game/chat logs.
 Output io.Writer
}

type StopPermit struct {
 Target string
 OperatorApproved bool
 TaskMigrationCompleted bool
 AcceptPlayerDisconnects bool
}

func validTarget(target string)bool {
 return target=="wild"||target=="playground"||target=="other"
}

func validSpec(s Spec) bool {
 return validTarget(s.Target)&&filepath.IsAbs(s.Executable)&&
  filepath.IsAbs(s.WorkingDirectory)&&len(s.Executable)>0&&len(s.Args)>0
}

// Controller owns exactly one process tree root launched by GSC. A controller
// is permanently scoped to one proxy ID; no process adoption or PID lookup.
type Controller struct {
 mu sync.Mutex
 target string
 spec Spec
 cmd *exec.Cmd
 stdin io.WriteCloser
 done chan error
 pending bool
}

func New(target string)(*Controller,error){
 if !validTarget(target){return nil,errors.New("invalid managed Velocity proxy")}
 return &Controller{target:target},nil
}

// Start only invokes an explicit absolute executable, with no shell or
// arbitrary script interpolation. The production host must independently
// verify the Java executable, jar path, port conflicts and migrated task.
func (c *Controller) Start(spec Spec) error {
 if c==nil||!validSpec(spec)||spec.Target!=c.target{
  return errors.New("untrusted Velocity launcher specification")
 }
 c.mu.Lock()
 defer c.mu.Unlock()
 if c.pending||c.cmd!=nil{return ErrBusy}
 cmd:=exec.Command(spec.Executable,spec.Args...)
 cmd.Dir=spec.WorkingDirectory
 if spec.Output!=nil {
  cmd.Stdout=spec.Output
  cmd.Stderr=spec.Output
 }
 stdin,err:=cmd.StdinPipe()
 if err!=nil{return err}
 c.pending=true
 if err:=cmd.Start();err!=nil{
  c.pending=false
  _=stdin.Close()
  return err
 }
 c.spec=spec
 c.cmd=cmd
 c.stdin=stdin
 finished:=make(chan error,1)
 c.done=finished
 c.pending=false
 go func(){
  err:=cmd.Wait()
  _=stdin.Close()
  c.mu.Lock()
  if c.cmd==cmd{
   c.cmd=nil
   c.stdin=nil
   c.done=nil
  }
  c.mu.Unlock()
  finished<-err
  close(finished)
 }()
 return nil
}

// Running is evidence that GSC still owns a process handle, NOT Java
// application-level health or proof that players are absent.
func(c *Controller) Running() bool{
 if c==nil{return false}
 c.mu.Lock();defer c.mu.Unlock()
 return c.cmd!=nil
}

// PID is intentionally NOT exposed in an API response. Callers must keep any
// identity proof inside the privileged host process.
func(c *Controller) OwnedPID()int{
 if c==nil{return 0}
 c.mu.Lock();defer c.mu.Unlock()
 if c.cmd==nil||c.cmd.Process==nil{return 0}
 return c.cmd.Process.Pid
}

func verifyPermit(p StopPermit,target string)bool{
 return p.Target==target&&p.OperatorApproved&&p.TaskMigrationCompleted&&
   p.AcceptPlayerDisconnects
}

// GracefulStop sends the REAL Velocity console shutdown command to a process
// launched by THIS controller, and waits for its confirmed exit. If the
// process does not exit, leave it running: NEVER terminate Java forcibly.
//
// All permit booleans are untrusted inputs until the host provides a real
// authenticated operator, explicit player-disconnect confirmation and
// verified Scheduler-to-GSC ownership cutover. The official Velocity console
// shutdown command gracefully disconnects players as part of normal exit.
// This package is intentionally not exported through the GSC HTTP interface.
func(c *Controller) GracefulStop(ctx context.Context,permit StopPermit)error{
 if c==nil||ctx==nil{return ErrNotOwned}
 if !verifyPermit(permit,c.target){return ErrPermit}
 c.mu.Lock()
 if c.pending||c.cmd==nil||c.stdin==nil||c.done==nil{
  c.mu.Unlock();return ErrNotOwned
 }
 c.pending=true
 stdin:=c.stdin
 done:=c.done
 c.mu.Unlock()
 defer func(){
  c.mu.Lock();c.pending=false;c.mu.Unlock()
 }()
 if _,err:=io.WriteString(stdin,"shutdown\n");err!=nil{return err}
 select{
 case err:=<-done:
  return err
 case <-ctx.Done():
  return ErrShutdownTimeout
 }
}

// RestartWithSpec allows the caller to revalidate JAR content and the exact
// launcher manifest BEFORE disconnecting players or stopping the old JVM.
// If validation fails, the existing owned proxy is left untouched.
func(c *Controller) RestartWithSpec(ctx context.Context,permit StopPermit,spec Spec)error{
 if c==nil||!validSpec(spec)||spec.Target!=c.target {
  return errors.New("refusing restart with an untrusted or wrong-target launcher")
 }
 if err:=c.GracefulStop(ctx,permit);err!=nil{return err}
 return c.Start(spec)
}

// Restart never performs a new Start if graceful exit failed. It is an
// explicit caller action, not a crash supervisor or task repair mechanism.
func(c *Controller) Restart(ctx context.Context,permit StopPermit)error{
 if c==nil{return ErrNotOwned}
 c.mu.Lock()
 spec:=c.spec
 c.mu.Unlock()
 if err:=c.GracefulStop(ctx,permit);err!=nil{return err}
 return c.Start(spec)
}

