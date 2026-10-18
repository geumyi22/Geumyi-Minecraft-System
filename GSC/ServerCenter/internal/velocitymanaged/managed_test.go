package velocitymanaged

import (
 "bufio"
 "context"
 "errors"
 "os"
 "path/filepath"
 "testing"
 "time"
)

// Subprocess under Go test ownership; no Java, real Velocity, Task
// Scheduler, firewall, world files, network sockets or production PIDs.
func TestManagedVelocityChild(t *testing.T){
 if os.Getenv("GSC452_MANAGED_CI_HELPER")!="true"{return}
 scanner:=bufio.NewScanner(os.Stdin)
 for scanner.Scan(){
  if scanner.Text()=="shutdown"{
   if os.Getenv("GSC452_MANAGED_CI_IGNORE_SHUTDOWN")=="true"{continue}
   os.Exit(0)
  }
  os.Exit(14)
 }
 os.Exit(15)
}

func helperSpec(t *testing.T,target string)Spec{
 t.Helper()
 executable,err:=os.Executable()
 if err!=nil{t.Fatal(err)}
 dir:=filepath.Dir(executable)
 return Spec{Target:target,Executable:executable,
  Args:[]string{"-test.run=^TestManagedVelocityChild$"},
  WorkingDirectory:dir}
}
func allowStop(target string)StopPermit{
 return StopPermit{Target:target,OperatorApproved:true,
  TaskMigrationCompleted:true,NoPlayersVerified:true,NewLoginsFenced:true}
}
func ownedCleanup(t *testing.T,c *Controller){
 t.Helper()
 t.Cleanup(func(){
  pid:=c.OwnedPID()
  if pid>0 {
   // Test-owned child ONLY: a cleanup signal cannot target a production JVM.
   if p,err:=os.FindProcess(pid);err==nil{
    _=p.Kill()
   }
  }
 })
}

func TestManagedProxyUsesRealConsoleShutdownWithoutForceKill(t *testing.T){
 t.Setenv("GSC452_MANAGED_CI_HELPER","true")
 t.Setenv("GSC452_MANAGED_CI_IGNORE_SHUTDOWN","false")
 for _,target:=range []string{"wild","playground","other"}{
  t.Run(target,func(t *testing.T){
   c,err:=New(target);if err!=nil{t.Fatal(err)}
   ownedCleanup(t,c)
   if err:=c.Start(helperSpec(t,target));err!=nil{t.Fatal(err)}
   if !c.Running()||c.OwnedPID()<=0{t.Fatal("GSC-owned child was not tracked")}
   if err:=c.Start(helperSpec(t,target));!errors.Is(err,ErrBusy){
     t.Fatalf("duplicate launched: %v",err)
   }
   for _,permit:=range []StopPermit{
    {Target:target},
    {Target:target,OperatorApproved:true,TaskMigrationCompleted:true,NoPlayersVerified:true},
    {Target:target,OperatorApproved:true,NoPlayersVerified:true,NewLoginsFenced:true},
    {Target:"other",OperatorApproved:true,TaskMigrationCompleted:true,NoPlayersVerified:true,NewLoginsFenced:true},
   }{
    if target=="other" && permit.Target=="other"&&permit.OperatorApproved&&permit.TaskMigrationCompleted&&permit.NoPlayersVerified&&permit.NewLoginsFenced{
      permit.Target="wild"
    }
    if err:=c.GracefulStop(context.Background(),permit);!errors.Is(err,ErrPermit){
      t.Fatalf("incomplete permission accepted: %v",err)
    }
    if !c.Running(){t.Fatal("unapproved stop terminated test-owned child")}
   }
   ctx,cancel:=context.WithTimeout(context.Background(),5*time.Second)
   defer cancel()
   if err:=c.GracefulStop(ctx,allowStop(target));err!=nil{t.Fatal(err)}
   if c.Running()||c.OwnedPID()!=0{t.Fatal("owned child not reaped after graceful shutdown")}
   if err:=c.GracefulStop(ctx,allowStop(target));!errors.Is(err,ErrNotOwned){
     t.Fatalf("foreign/unowned stop allowed: %v",err)
   }
  })
 }
}

func TestManagedProxyRestartWaitsForGracefulExit(t *testing.T){
 t.Setenv("GSC452_MANAGED_CI_HELPER","true")
 t.Setenv("GSC452_MANAGED_CI_IGNORE_SHUTDOWN","false")
 c,_:=New("wild")
 ownedCleanup(t,c)
 spec:=helperSpec(t,"wild")
 if err:=c.Start(spec);err!=nil{t.Fatal(err)}
 first:=c.OwnedPID()
 ctx,cancel:=context.WithTimeout(context.Background(),10*time.Second)
 defer cancel()
 if err:=c.Restart(ctx,allowStop("wild"));err!=nil{t.Fatal(err)}
 next:=c.OwnedPID()
 if next<=0||next==first{t.Fatal("GSC did not launch new owned generation")}
 if err:=c.GracefulStop(ctx,allowStop("wild"));err!=nil{t.Fatal(err)}
}

func TestManagedProxyTimeoutNeverForceKillsOrRestarts(t *testing.T){
 t.Setenv("GSC452_MANAGED_CI_HELPER","true")
 t.Setenv("GSC452_MANAGED_CI_IGNORE_SHUTDOWN","true")
 c,_:=New("playground")
 ownedCleanup(t,c)
 if err:=c.Start(helperSpec(t,"playground"));err!=nil{t.Fatal(err)}
 pid:=c.OwnedPID()
 ctx,cancel:=context.WithTimeout(context.Background(),150*time.Millisecond)
 defer cancel()
 if err:=c.Restart(ctx,allowStop("playground"));!errors.Is(err,ErrShutdownTimeout){
  t.Fatalf("timeout unexpectedly launched a replacement: %v",err)
 }
 if !c.Running()||c.OwnedPID()!=pid{
   t.Fatal("timeout killed/replaced a still-running test-owned JVM")
 }
 if err:=c.Start(helperSpec(t,"playground"));!errors.Is(err,ErrBusy){
   t.Fatal("timeout permitted duplicate Java process")
 }
}

func TestManagedProxyRejectsInvalidOrForeignLaunchers(t *testing.T){
 for _,target:=range []string{"", "lobby", "../wild", "wild;shutdown"}{
  if _,err:=New(target);err==nil{t.Fatalf("invalid target accepted: %q",target)}
 }
 c,_:=New("wild")
 for _,spec:=range []Spec{
  {},
  {Target:"other",Executable:"/tmp/java",WorkingDirectory:"/tmp",Args:[]string{"-jar","velocity.jar"}},
  {Target:"wild",Executable:"java",WorkingDirectory:"/tmp",Args:[]string{"-jar","velocity.jar"}},
  {Target:"wild",Executable:"/tmp/java",WorkingDirectory:"relative",Args:[]string{"-jar","velocity.jar"}},
  {Target:"wild",Executable:"/tmp/java",WorkingDirectory:"/tmp"},
 }{
  if err:=c.Start(spec);err==nil{
   t.Fatalf("bad process spec accepted: %+v",spec)
  }
 }
}
