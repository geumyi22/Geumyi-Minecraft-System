package velocitymanaged

import (
 "context"
 "errors"
 "net"
 "os"
 "path/filepath"
 "runtime"
 "testing"
 "time"
)

// ONLY runs on GitHub Windows CI with a SHA-verified official Velocity JAR.
// This verifies an actual Velocity JVM started by the new GSC-owned process
// controller can exit on its built-in console "shutdown" command, restart,
// and exit again. Never accesses Task Scheduler or production servers.
func TestOfficialVelocity420ManagedConsoleLifecycleCI(t *testing.T){
 jar:=os.Getenv("GSC452_CI_VELOCITY420_JAR")
 if jar==""{t.Skip("requires SHA-pinned official Velocity in disposable Windows CI")}
 if runtime.GOOS!="windows"||os.Getenv("GITHUB_ACTIONS")!="true"||
    os.Getenv("RUNNER_OS")!="Windows"{
    t.Fatal("real official Velocity fixture only allowed on disposable GitHub Windows CI")
 }
 stat,err:=os.Stat(jar)
 if err!=nil||stat.IsDir(){t.Fatal("CI verified Velocity artifact missing")}
 java:=filepath.Join(os.Getenv("JAVA_HOME"),"bin","java.exe")
 if _,err:=os.Stat(java);err!=nil{t.Fatal("CI JDK25 executable missing")}
 root:=t.TempDir()
 c,err:=New("wild");if err!=nil{t.Fatal(err)}
 t.Cleanup(func(){
   if pid:=c.OwnedPID();pid>0{
     // CI test-owned process, emergency cleanup ONLY on a failed test.
     if p,e:=os.FindProcess(pid);e==nil{_ = p.Kill()}
   }
 })
 spec:=Spec{Target:"wild",Executable:java,
   Args:[]string{"-jar",jar},WorkingDirectory:root}
 // Do not confuse an already occupied port with the CI-owned JVM.
 free,err:=net.Listen("tcp","127.0.0.1:25565")
 if err!=nil{t.Fatalf("CI host port unavailable before start: %v",err)}
 _=free.Close()
 if err:=c.Start(spec);err!=nil{t.Fatalf("disposable Velocity start: %v",err)}
 waitReady:=func()error{
   deadline:=time.Now().Add(35*time.Second)
   for time.Now().Before(deadline){
     conn,e:=net.DialTimeout("tcp","127.0.0.1:25565",300*time.Millisecond)
     if e==nil{_ =conn.Close();return nil}
     if !c.Running(){return errors.New("disposable proxy exited before listen")}
     time.Sleep(250*time.Millisecond)
   }
   return errors.New("Velocity did not listen on expected disposable CI port")
 }
 if err:=waitReady();err!=nil{t.Fatal(err)}
 old:=c.OwnedPID()
 if old<=0{t.Fatal("untracked official Velocity JVM")}
 ctx,cancel:=context.WithTimeout(context.Background(),25*time.Second)
 defer cancel()
 if err:=c.Restart(ctx,allowStop("wild"));err!=nil{
   t.Fatalf("official console shutdown/restart failed: %v",err)
 }
 if next:=c.OwnedPID();next<=0||next==old{t.Fatal("official JVM was not replaced")}
 if err:=waitReady();err!=nil{t.Fatal(err)}
 stopCtx,stopCancel:=context.WithTimeout(context.Background(),25*time.Second)
 defer stopCancel()
 if err:=c.GracefulStop(stopCtx,allowStop("wild"));err!=nil{
   t.Fatalf("official Velocity console stop failed: %v",err)
 }
 if c.Running()||c.OwnedPID()!=0{t.Fatal("official Velocity left owned JVM after shutdown")}
 t.Log("OFFICIAL_VELOCITY420_GSC_OWNED_CONSOLE_SHUTDOWN_RESTART_PASS CI ONLY")
}
