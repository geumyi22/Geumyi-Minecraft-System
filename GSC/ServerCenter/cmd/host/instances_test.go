package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func isolatedInstanceCatalog(t *testing.T) string {
	t.Helper()
	oldPath := configPath
	oldConfig := configSnapshot()
	instanceCatalogMu.Lock()
	oldReservations := instanceReservations
	instanceReservations = map[string]bool{}
	instanceCatalogMu.Unlock()
	instanceRuntimeMu.Lock()
	oldRuntimes := instanceRuntimes
	instanceRuntimes = map[string]*instanceRuntimeState{}
	instanceRuntimeMu.Unlock()
	root := t.TempDir()
	configPath = filepath.Join(root, "host", "server.json")
	configMu.Lock()
	cfg = Config{Port: 8787, APIToken: "instance-test-token", AllowLoopbackNoAuth: true}
	configMu.Unlock()
	t.Cleanup(func() {
		configPath = oldPath
		configMu.Lock()
		cfg = oldConfig
		configMu.Unlock()
		instanceCatalogMu.Lock()
		instanceReservations = oldReservations
		instanceCatalogMu.Unlock()
		instanceRuntimeMu.Lock()
		instanceRuntimes = oldRuntimes
		instanceRuntimeMu.Unlock()
	})
	return root
}

func instanceFixture(t *testing.T, root, id string, port int) ManagedInstance {
	t.Helper()
	dir := filepath.Join(root, id)
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "server.jar"), []byte("unchanged jar"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte(fmt.Sprintf("server-port=%d\n", port)), 0600); err != nil {
		t.Fatal(err)
	}
	return ManagedInstance{ID: id, Name: id, Kind: "fabric", Dir: dir, MemoryMB: 2048, LaunchMode: "jar", LaunchFile: "server.jar", JavaPort: port}
}

func TestInstancesImportPreservesFilesAndLegacyCatalog(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "fabric", 26345)
	if err := os.MkdirAll(filepath.Dir(configPath), 0700); err != nil {
		t.Fatal(err)
	}
	legacy := []byte("original server configuration\n")
	if err := os.WriteFile(configPath, legacy, 0600); err != nil {
		t.Fatal(err)
	}
	beforeJar, _ := os.ReadFile(filepath.Join(p.Dir, "server.jar"))
	beforeProps, _ := os.ReadFile(filepath.Join(p.Dir, "server.properties"))
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	got, err := listManagedInstances()
	if err != nil || len(got) != 1 || got[0].ID != p.ID {
		t.Fatalf("catalog: %#v %v", got, err)
	}
	for path, want := range map[string][]byte{configPath: legacy, filepath.Join(p.Dir, "server.jar"): beforeJar, filepath.Join(p.Dir, "server.properties"): beforeProps} {
		b, err := os.ReadFile(path)
		if err != nil || !bytes.Equal(b, want) {
			t.Fatalf("existing file changed: %s", path)
		}
	}
	if err := addManagedInstance(p); err == nil {
		t.Fatal("duplicate accepted")
	}
	bad := p
	bad.ID = "child"
	bad.Dir = filepath.Join(p.Dir, "world")
	bad.JavaPort++
	if _, err := validateManagedInstance(bad); err == nil {
		t.Fatal("nested directory accepted")
	}
	bad = p
	bad.ID = "second"
	bad.Dir = filepath.Join(root, "different")
	if _, err := validateManagedInstance(bad); err == nil {
		t.Fatal("duplicate port accepted")
	}
}

func TestInstancesImportAdditionalJavaServerKinds(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	for i, kind := range []string{"Spigot", " VANILLA ", "purpur"} {
		id := strings.ToLower(strings.TrimSpace(kind))
		p := instanceFixture(t, root, id, 26400+i)
		p.Kind = kind
		p.LaunchMode = ""
		p.JavaPath = os.Args[0] // Command construction only; never execute the fixture JAR.
		before, err := os.ReadFile(filepath.Join(p.Dir, "server.properties"))
		if err != nil {
			t.Fatal(err)
		}
		if err := addManagedInstance(p); err != nil {
			t.Fatalf("import %s: %v", kind, err)
		}
		saved, err := instanceByID(id)
		if err != nil || saved.Kind != id || saved.LaunchMode != "jar" {
			t.Fatalf("normalized profile %s: %+v %v", kind, saved, err)
		}
		cmd, err := instanceLaunchCommand(saved)
		if err != nil {
			t.Fatal(err)
		}
		if len(cmd.Args) < 5 || strings.Join(cmd.Args[len(cmd.Args)-3:], "|") != strings.Join([]string{"-jar", filepath.Join(p.Dir, "server.jar"), "nogui"}, "|") {
			t.Fatalf("unexpected generic Java launch for %s: %v", kind, cmd.Args)
		}
		after, err := os.ReadFile(filepath.Join(p.Dir, "server.properties"))
		if err != nil || !bytes.Equal(before, after) {
			t.Fatalf("import changed %s server configuration", kind)
		}
		if _, err := os.Stat(filepath.Join(p.Dir, "plugins")); !os.IsNotExist(err) {
			t.Fatalf("import installed plugins for %s: %v", kind, err)
		}
	}
	bad := instanceFixture(t, root, "unsupported", 26410)
	bad.Kind = "unknown-loader"
	if err := addManagedInstance(bad); err == nil {
		t.Fatal("unsupported kind was accepted")
	}
	profiles, err := listManagedInstances()
	if err != nil || len(profiles) != 3 {
		t.Fatalf("unsupported import changed catalog: %d %v", len(profiles), err)
	}
}

func TestInstancesDirectJavaUsesUTF8AndLeavesCustomScriptsUntouched(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	for i, kind := range []string{"fabric", "forge", "neoforge", "custom-script"} {
		t.Run(kind, func(t *testing.T) {
			p := instanceFixture(t, root, kind, 26420+i)
			p.JavaPath = os.Args[0] // Inspect launcher arguments without a Java dependency.
			p.Kind = kind
			var script []byte
			if kind != "fabric" {
				p.LaunchMode = "script"
				p.LaunchFile = "run.bat"
				script = []byte("@java -Dfile.encoding=MS949 -jar custom.jar\r\n")
				if kind == "forge" || kind == "neoforge" {
					if err := os.MkdirAll(filepath.Join(p.Dir, "libraries", "loader"), 0700); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(p.Dir, "libraries", "loader", "win_args.txt"), []byte("LoaderMain\n"), 0600); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(p.Dir, "user_jvm_args.txt"), []byte("-Dfile.encoding=MS949\n"), 0600); err != nil {
						t.Fatal(err)
					}
					script = []byte("@java @user_jvm_args.txt @libraries/loader/win_args.txt %*\r\n")
				}
				if err := os.WriteFile(filepath.Join(p.Dir, p.LaunchFile), script, 0600); err != nil {
					t.Fatal(err)
				}
			}
			cmd, err := instanceLaunchCommand(p)
			if err != nil {
				t.Fatal(err)
			}
			args := strings.Join(cmd.Args, " ")
			if kind == "custom-script" {
				if strings.Contains(args, "encoding=UTF-8") {
					t.Fatalf("custom script arguments were changed: %v", cmd.Args)
				}
			} else {
				for _, flag := range []string{"-Dfile.encoding=UTF-8", "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-Dsun.stdout.encoding=UTF-8", "-Dsun.stderr.encoding=UTF-8"} {
					if !strings.Contains(args, flag) {
						t.Fatalf("missing output encoding %s in %v", flag, cmd.Args)
					}
				}
				if kind != "fabric" && strings.Index(args, "@user_jvm_args.txt") > strings.Index(args, "-Dfile.encoding=UTF-8") {
					t.Fatalf("user JVM file can override transport encoding: %v", cmd.Args)
				}
			}
			if script != nil {
				after, err := os.ReadFile(filepath.Join(p.Dir, p.LaunchFile))
				if err != nil || !bytes.Equal(script, after) {
					t.Fatal("existing launch script was modified")
				}
			}
		})
	}
}

func TestInstancesRejectLegacyOverlapAndPortMismatch(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "mod", 26346)
	configMu.Lock()
	cfg.Servers = []ServerConfig{{ID: "legacy", Name: "Original Paper", Path: p.Dir, JavaPort: 26347}}
	configMu.Unlock()
	if _, err := validateManagedInstance(p); err == nil {
		t.Fatal("legacy directory accepted")
	}
	p.Dir = filepath.Join(root, "another")
	p.JavaPort = 26347
	if _, err := validateManagedInstance(p); err == nil {
		t.Fatal("legacy port accepted")
	}
	configMu.Lock()
	cfg.Servers = nil
	configMu.Unlock()
	p.Dir = filepath.Join(root, "mod")
	p.JavaPort = 26348
	if err := verifyInstanceFiles(p); err == nil {
		t.Fatal("mismatched port accepted")
	}
}

func TestInstancesReservationAndOperationExclusion(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "new", 26349)
	release, err := reserveInstanceDirectory(p.Dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := addManagedInstance(p); err == nil {
		t.Fatal("registered during installation")
	}
	release()
	release()
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if beginInstanceOperation(p.ID, "restart") {
				accepted.Add(1)
			}
		}()
	}
	wg.Wait()
	if accepted.Load() != 1 {
		t.Fatalf("concurrent operations: %d", accepted.Load())
	}
	endInstanceOperation(p.ID, nil)
	if !beginInstanceOperation(p.ID, "stop") {
		t.Fatal("lock remained after completion")
	}
	endInstanceOperation(p.ID, nil)
}

func TestInstancesMutationRequiresActualTokenDespiteLoopback(t *testing.T) {
	isolatedInstanceCatalog(t)
	called := false
	h := withInstanceMutationAuth(func(w http.ResponseWriter, r *http.Request) { called = true; w.WriteHeader(204) })
	for _, token := range []string{"", "wrong"} {
		r := httptest.NewRequest("POST", "http://localhost:8787/api/v5/instances/import", strings.NewReader("{}"))
		r.RemoteAddr = "127.0.0.1:1234"
		r.Header.Set("X-GSC-Token", token)
		w := httptest.NewRecorder()
		h(w, r)
		if w.Code != 401 || called {
			t.Fatalf("accepted wrong/missing token: %d", w.Code)
		}
	}
	r := httptest.NewRequest("POST", "http://localhost:8787/api/v5/instances/import", nil)
	r.RemoteAddr = "127.0.0.1:1234"
	r.Header.Set("X-GSC-Token", "instance-test-token")
	w := httptest.NewRecorder()
	h(w, r)
	if w.Code != 204 || !called {
		t.Fatalf("valid token rejected %d", w.Code)
	}
	called = false
	r.Header.Set("Origin", "https://untrusted.example")
	w = httptest.NewRecorder()
	h(w, r)
	if w.Code != 403 || called {
		t.Fatal("cross-origin mutation accepted")
	}
}

func TestInstancesExternalListenerNeverAdoptedOrStopped(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	port := listener.Addr().(*net.TCPAddr).Port
	p := instanceFixture(t, root, "outside", port)
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	s := managedInstanceStatus(p)
	if s.Status != "external" || s.CanStart || s.CanStop {
		t.Fatalf("unsafe external state: %+v", s)
	}
	if err := runManagedInstanceAction(p, "restart"); err == nil {
		t.Fatal("external restart accepted")
	}
	if !instancePortOpen(port) {
		t.Fatal("external listener stopped")
	}
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("Host shutdown ignored external instance")
	}
}

// Helper uses a real subprocess and stdin, with no Java server or real world.
func TestInstanceProcessHelper(t *testing.T) {
	if os.Getenv("GSC_INSTANCE_HELPER") != "1" {
		return
	}
	l, err := net.Listen("tcp", "127.0.0.1:"+os.Getenv("GSC_INSTANCE_HELPER_PORT"))
	if err != nil {
		os.Exit(7)
	}
	f, err := os.OpenFile("boots.txt", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		os.Exit(8)
	}
	_, _ = fmt.Fprintln(f, "boot")
	_ = f.Close()
	go func() {
		for {
			c, e := l.Accept()
			if e != nil {
				return
			}
			_ = c.Close()
		}
	}()
	scan := bufio.NewScanner(os.Stdin)
	for scan.Scan() {
		if scan.Text() == "stop" {
			_ = l.Close()
			os.Exit(0)
		}
	}
	_ = l.Close()
	os.Exit(9)
}

func TestInstancesRealSubprocessStopRestart(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows script lifecycle")
	}
	root := isolatedInstanceCatalog(t)
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	_ = l.Close()
	p := instanceFixture(t, root, "process", port)
	p.LaunchMode = "script"
	p.LaunchFile = "run.cmd"
	p.JavaPath = os.Args[0]
	if err := os.WriteFile(filepath.Join(p.Dir, p.LaunchFile), []byte("@\""+os.Args[0]+"\" -test.run=^TestInstanceProcessHelper$\r\npause\r\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GSC_INSTANCE_HELPER", "1")
	t.Setenv("GSC_INSTANCE_HELPER_PORT", fmt.Sprint(port))
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = stopManagedInstance(p) })
	if err := startManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	wait := func() {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			if instancePortOpen(port) {
				return
			}
			time.Sleep(30 * time.Millisecond)
		}
		t.Fatal("subprocess failed to listen")
	}
	wait()
	if err := startManagedInstance(p); err == nil {
		t.Fatal("duplicate process started")
	}
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("Host shutdown allowed active stdin process")
	}
	if err := runManagedInstanceAction(p, "restart"); err != nil {
		t.Fatal(err)
	}
	wait()
	if err := stopManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	if instancePortOpen(port) {
		t.Fatal("listener remained after successful stop")
	}
	boots, err := os.ReadFile(filepath.Join(p.Dir, "boots.txt"))
	if err != nil || strings.Count(string(boots), "boot") != 2 {
		t.Fatalf("expected exactly 2 starts: %q %v", boots, err)
	}
	if err := managedInstanceShutdownBlock(); err != nil {
		t.Fatal(err)
	}
}

type instanceTestInput struct{ bytes.Buffer }

func (i *instanceTestInput) Close() error { return nil }

func TestInstancesRestartStopsOnShutdownTimeout(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "hung", 26350)
	input := &instanceTestInput{}
	proc := &instanceProcess{stdin: input, done: make(chan struct{})}
	instanceRuntimeMu.Lock()
	instanceRuntimeLocked(p.ID).process = proc
	instanceRuntimeMu.Unlock()
	old := instanceStopTimeout
	instanceStopTimeout = 15 * time.Millisecond
	defer func() { instanceStopTimeout = old }()
	err := runManagedInstanceAction(p, "restart")
	if err == nil || !strings.Contains(err.Error(), "대기 시간") {
		t.Fatalf("expected timeout: %v", err)
	}
	if input.String() != "stop\n" {
		t.Fatalf("unexpected command %q", input.String())
	}
	if !instanceProcessAlive(proc) {
		t.Fatal("timeout killed original process")
	}
}

func TestInstancesPreviousHostReceiptBlocksBeforePortOpens(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "previous", 26351)
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	receipt, err := prepareInstanceReceipt(p)
	if err != nil {
		t.Fatal(err)
	}
	if blocked, _ := instanceReceiptBlocks(p); !blocked {
		t.Fatal("pending launch allowed a second start")
	}
	receipt.State = "running"
	receipt.PID = os.Getpid()
	alive, created, err := instanceProcessIdentity(receipt.PID)
	if err != nil || !alive {
		t.Fatalf("process identity: %v %v", alive, err)
	}
	receipt.ProcessCreated = created
	if err := writeInstanceReceipt(p, receipt); err != nil {
		t.Fatal(err)
	}
	// No in-memory process and no listening port, as during a previous JVM's startup.
	s := managedInstanceStatus(p)
	if s.Status != "external" || s.CanStart || s.CanStop {
		t.Fatalf("unsafe previous-host status: %+v", s)
	}
	if err := startManagedInstance(p); err == nil {
		t.Fatal("duplicate launch allowed before listener opened")
	}
	if err := stopManagedInstance(p); err == nil {
		t.Fatal("previous-host PID was adopted for termination")
	}
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("previous-host receipt ignored")
	}
	if alive, _, err := instanceProcessIdentity(os.Getpid()); err != nil || !alive {
		t.Fatal("test process was changed")
	}
	clearInstanceReceipt(p, receipt)
	if blocked, why := instanceReceiptBlocks(p); blocked {
		t.Fatalf("receipt was not removed: %s", why)
	}
}

func TestInstancesShutdownRejectsOperationAlreadyWaitingForLock(t *testing.T) {
	isolatedInstanceCatalog(t)
	old := shuttingDown.Swap(false)
	t.Cleanup(func() { shuttingDown.Store(old) })
	instanceRuntimeMu.Lock()
	accepted := make(chan bool, 1)
	go func() { accepted <- beginInstanceOperation("waiting", "start") }()
	shuttingDown.Store(true)
	instanceRuntimeMu.Unlock()
	if <-accepted {
		t.Fatal("operation waiting at shutdown was accepted")
	}
	instanceRuntimeMu.Lock()
	_, exists := instanceRuntimes["waiting"]
	instanceRuntimeMu.Unlock()
	if exists {
		t.Fatal("rejected shutdown request created runtime work")
	}
	if err := managedInstanceShutdownBlock(); err != nil {
		t.Fatalf("rejected work incorrectly blocked shutdown: %v", err)
	}
}

func TestInstancesShutdownChecksRuntimeBeforeCatalog(t *testing.T) {
	isolatedInstanceCatalog(t)
	old := shuttingDown.Swap(false)
	t.Cleanup(func() { shuttingDown.Store(old) })
	if !beginInstanceOperation("not-yet-listed", "start") {
		t.Fatal("failed to start pre-shutdown operation")
	}
	shuttingDown.Store(true)
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("catalog omission hid an operation from shutdown guard")
	}
	endInstanceOperation("not-yet-listed", nil)
	instanceRuntimeMu.Lock()
	proc := &instanceProcess{done: make(chan struct{})}
	instanceRuntimeLocked("not-yet-listed").process = proc
	instanceRuntimeMu.Unlock()
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("catalog omission hid a live process from shutdown guard")
	}
	close(proc.done)
	if err := managedInstanceShutdownBlock(); err != nil {
		t.Fatalf("completed operation still blocked shutdown: %v", err)
	}
}

func TestInstancesVelocityOwnershipDefaultsAndIsolation(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "proxy-new", 26420)
	p.Kind = "velocity"
	p.TaskName = "Geumyi Day10 Velocity wild"
	p.BridgePort = 28901
	legacy, err := validateInstanceShape(p)
	if err != nil || legacy.ManagementMode != "scheduler" || !isScheduledProxy(legacy) {
		t.Fatalf("legacy Velocity ownership changed: %+v %v", legacy, err)
	}
	// Reading an existing catalog supplies the default without rewriting it.
	if err := os.MkdirAll(filepath.Dir(instanceCatalogPath()), 0700); err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(instanceCatalog{Schema: 1, Instances: []ManagedInstance{p}})
	if err := os.WriteFile(instanceCatalogPath(), b, 0600); err != nil {
		t.Fatal(err)
	}
	profiles, err := listManagedInstances()
	if err != nil || len(profiles) != 1 || profiles[0].ManagementMode != "scheduler" {
		t.Fatalf("legacy catalog default: %+v %v", profiles, err)
	}
	after, _ := os.ReadFile(instanceCatalogPath())
	if !bytes.Equal(b, after) {
		t.Fatal("reading ownership default rewrote existing catalog")
	}
	newProxy := p
	newProxy.ManagementMode = "gsc"
	if _, err := validateInstanceShape(newProxy); err == nil {
		t.Fatal("GSC proxy accepted Scheduler fields")
	}
	newProxy.TaskName = ""
	newProxy.BridgePort = 0
	newProxy, err = validateInstanceShape(newProxy)
	if err != nil || isScheduledProxy(newProxy) || newProxy.ManagementMode != "gsc" {
		t.Fatalf("new proxy GSC mode rejected: %+v %v", newProxy, err)
	}
	newProxy.Dir = filepath.Join(externalProxyRoot(), "wild")
	newProxy.ID = "unsafe-adoption"
	if _, err := validateManagedInstance(newProxy); err == nil {
		t.Fatal("GSC proxy adopted protected Scheduler directory")
	}
	bad := newProxy
	bad.Kind = "paper"
	bad.ManagementMode = "scheduler"
	if _, err := validateInstanceShape(bad); err == nil {
		t.Fatal("Paper accepted Scheduler ownership")
	}
}

type instanceShutdownInput struct {
	bytes.Buffer
	done chan struct{}
	once sync.Once
}

func (i *instanceShutdownInput) Close() error {
	i.once.Do(func() { close(i.done) })
	return nil
}

func TestInstancesGSCVelocityConsoleShutdownAndReceipt(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "velocity-gsc", 26421)
	p.Kind = "velocity"
	p.ManagementMode = "gsc"
	if err := os.WriteFile(filepath.Join(p.Dir, "velocity.toml"), []byte("bind = \"0.0.0.0:26421\" # public port\n[servers]\nlobby = \"127.0.0.1:25565\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := verifyInstanceFiles(p); err != nil {
		t.Fatal(err)
	}
	bad := p
	bad.JavaPort++
	if err := verifyInstanceFiles(bad); err == nil {
		t.Fatal("Velocity accepted mismatched listener port")
	}
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	receipt, err := prepareInstanceReceipt(p)
	if err != nil {
		t.Fatal(err)
	}
	if blocked, _ := instanceReceiptBlocks(p); !blocked {
		t.Fatal("GSC Velocity bypassed previous launch receipt")
	}
	clearInstanceReceipt(p, receipt)
	input := &instanceShutdownInput{done: make(chan struct{})}
	proc := &instanceProcess{stdin: input, done: input.done}
	instanceRuntimeMu.Lock()
	instanceRuntimeLocked(p.ID).process = proc
	instanceRuntimeMu.Unlock()
	request := func(command string) *httptest.ResponseRecorder {
		body, _ := json.Marshal(map[string]string{"id": p.ID, "command": command})
		r := httptest.NewRequest("POST", "/api/v5/instances/command", bytes.NewReader(body))
		w := httptest.NewRecorder()
		apiInstanceCommand(w, r)
		return w
	}
	if w := request("glist"); w.Code != http.StatusOK || input.String() != "glist\n" {
		t.Fatalf("GSC Velocity console failed: %d %q", w.Code, input.String())
	}
	for _, command := range []string{"stop", "shutdown", "/shutdown", "restart", "end", "velocity:shutdown"} {
		if w := request(command); w.Code != http.StatusBadRequest {
			t.Fatalf("console lifecycle bypass accepted: %s %d", command, w.Code)
		}
	}
	prepare := httptest.NewRecorder()
	apiInstancePrepare(prepare, httptest.NewRequest("POST", "/api/v5/instances/prepare", strings.NewReader(`{"id":"velocity-gsc"}`)))
	if prepare.Code != http.StatusBadRequest {
		t.Fatal("new GSC Velocity accepted Scheduler bridge preparation")
	}
	if err := managedInstanceShutdownBlock(); err == nil {
		t.Fatal("Host shutdown ignored active GSC Velocity")
	}
	if err := runManagedInstanceAction(p, "stop"); err != nil {
		t.Fatal(err)
	}
	if input.String() != "glist\nshutdown\n" {
		t.Fatalf("wrong Velocity shutdown command: %q", input.String())
	}
	if err := managedInstanceShutdownBlock(); err != nil {
		t.Fatal(err)
	}
}

func TestInstancesGSCReadyRequiresMinecraftResponse(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	var ready atomic.Bool
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				if !ready.Load() {
					return
				}
				_ = conn.SetDeadline(time.Now().Add(time.Second))
				reader := bufio.NewReader(conn)
				for range 2 {
					n, err := readVarInt(reader)
					if err != nil || n < 0 || n > 4096 {
						return
					}
					if _, err := io.CopyN(io.Discard, reader, int64(n)); err != nil {
						return
					}
				}
				body := `{"version":{"name":"Velocity fixture","protocol":776},"players":{"max":20,"online":3},"description":{"text":"ready"}}`
				var packet bytes.Buffer
				writeVarInt(&packet, 0)
				writeVarInt(&packet, len(body))
				packet.WriteString(body)
				sendPacket(conn, packet.Bytes())
			}()
		}
	}()
	for _, kind := range []string{"paper", "spigot", "purpur", "vanilla", "fabric", "forge", "neoforge", "velocity"} {
		t.Run(kind, func(t *testing.T) {
			p := instanceFixture(t, root, kind+"-ready", listener.Addr().(*net.TCPAddr).Port)
			p.Kind, p.ManagementMode = kind, "gsc"
			proc := &instanceProcess{cmd: &exec.Cmd{Process: &os.Process{Pid: os.Getpid()}}, done: make(chan struct{})}
			defer close(proc.done)
			instanceRuntimeMu.Lock()
			instanceRuntimeLocked(p.ID).process = proc
			instanceRuntimeMu.Unlock()
			ready.Store(false)
			if state := managedInstanceStatus(p); state.Status != "starting" || state.Players != -1 || state.CanStart || !state.CanStop {
				t.Fatalf("bare TCP listener was marked ready: %+v", state)
			}
			ready.Store(true)
			if state := managedInstanceStatus(p); state.Status != "online" || state.Players != 3 {
				t.Fatalf("Minecraft status response was not accepted: %+v", state)
			}
		})
	}
}

func TestInstancesProxyBackendMetadataPreservedWithoutReconfiguration(t *testing.T) {
	root := isolatedInstanceCatalog(t)
	p := instanceFixture(t, root, "backend", 26430)
	p.ProxyBackend = true
	if err := addManagedInstance(p); err != nil {
		t.Fatal(err)
	}
	saved, err := instanceByID(p.ID)
	if err != nil || !saved.ProxyBackend {
		t.Fatalf("backend metadata not persisted: %+v %v", saved, err)
	}
	before, _ := os.ReadFile(filepath.Join(p.Dir, "server.properties"))
	update := func(profile ManagedInstance) *httptest.ResponseRecorder {
		body, _ := json.Marshal(profile)
		w := httptest.NewRecorder()
		apiUpdateInstance(w, httptest.NewRequest("POST", "/api/v5/instances/update", bytes.NewReader(body)))
		return w
	}
	saved.Name = "Renamed backend"
	if w := update(saved); w.Code != http.StatusOK {
		t.Fatalf("ordinary profile update rejected: %d %s", w.Code, w.Body.String())
	}
	saved.ProxyBackend = false
	if w := update(saved); w.Code != http.StatusBadRequest {
		t.Fatalf("backend configuration changed through metadata edit: %d", w.Code)
	}
	after, _ := os.ReadFile(filepath.Join(p.Dir, "server.properties"))
	if !bytes.Equal(before, after) {
		t.Fatal("profile metadata edit rewrote server configuration")
	}
	stored, err := instanceByID(p.ID)
	if err != nil || !stored.ProxyBackend || stored.Name != "Renamed backend" {
		t.Fatalf("failed update changed backend profile: %+v %v", stored, err)
	}
	saved.Kind, saved.ManagementMode, saved.ProxyBackend = "velocity", "gsc", true
	if _, err := validateInstanceShape(saved); err == nil {
		t.Fatal("Velocity was accepted as a proxy backend")
	}
}
