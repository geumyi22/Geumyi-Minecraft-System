package main

import (
	"bytes"
	"context"
	"crypto/rand"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
)

//go:embed assets/gsc-velocity-control.jar
var instanceProxyPlugin []byte

type instanceProxySecret struct {
	ID        string `json:"id"`
	Directory string `json:"directory"`
	Port      int    `json:"port"`
	Token     string `json:"token"`
}

type instanceProxyBridge struct {
	PID       int    `json:"pid"`
	StartTime int64  `json:"start_time"`
	Directory string `json:"directory"`
	Players   int    `json:"players"`
	JavaPort  int    `json:"java_port"`
	Stopping  bool   `json:"stopping"`
}

type instanceProxyTask struct {
	Count      int    `json:"count"`
	Name       string `json:"name"`
	Path       string `json:"path"`
	State      string `json:"state"`
	Enabled    bool   `json:"enabled"`
	Directory  string `json:"directory"`
	Executable string `json:"executable"`
	Arguments  string `json:"arguments"`
	Principal  string `json:"principal"`
	Actions    int    `json:"actions"`
	LastResult int64  `json:"last_result"`
	TCPBusy    bool   `json:"tcp_busy"`
	UDPBusy    bool   `json:"udp_busy"`
	BridgeBusy bool   `json:"bridge_busy"`
}

var instanceProxyIDPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)
var instanceProxyJarPattern = regexp.MustCompile(`(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|(\S+))`)

func instanceProxySameDir(a, b string) bool {
	a, ea := filepath.Abs(a)
	b, eb := filepath.Abs(b)
	if ea != nil || eb != nil {
		return false
	}
	if real, err := filepath.EvalSymlinks(a); err == nil {
		a = real
	}
	if real, err := filepath.EvalSymlinks(b); err == nil {
		b = real
	}
	return strings.EqualFold(filepath.Clean(a), filepath.Clean(b))
}

// Limit Scheduler actions to the three existing, named proxy tasks. Never adopt an arbitrary task.
func instanceProxyTarget(p ManagedInstance) (externalProxyTarget, error) {
	if !isScheduledProxy(p) {
		return externalProxyTarget{}, errors.New("GSC 직접 실행 프록시에는 기존 예약 작업 제어를 적용하지 않습니다")
	}
	if runtime.GOOS != "windows" {
		return externalProxyTarget{}, errors.New("Velocity 작업 제어는 Windows에서 지원합니다")
	}
	if !instanceProxyIDPattern.MatchString(p.ID) || p.BridgePort < 1024 || p.BridgePort > 65535 {
		return externalProxyTarget{}, errors.New("프록시 ID 또는 로컬 제어 포트가 올바르지 않습니다")
	}
	for _, t := range day11ExternalProxyTargets {
		if p.TaskName == t.TaskName && p.JavaPort == t.PublicJava &&
			instanceProxySameDir(p.Dir, filepath.Join(externalProxyRoot(), t.ID)) {
			if p.BridgePort == t.PublicJava || p.BridgePort == t.PublicBedrock {
				break
			}
			return t, nil
		}
	}
	return externalProxyTarget{}, errors.New("기존 프록시 찾기로 등록한 세 Velocity 작업만 제어할 수 있습니다. 경로·작업 이름·포트를 확인해 주세요")
}

func instanceProxyPowershell(ctx context.Context, script string, env []string) ([]byte, error) {
	u := utf16.Encode([]rune(script))
	b := make([]byte, len(u)*2)
	for i, v := range u {
		b[i*2], b[i*2+1] = byte(v), byte(v>>8)
	}
	c := exec.CommandContext(ctx, "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", base64.StdEncoding.EncodeToString(b))
	c.Env = append(os.Environ(), env...)
	hideProcess(c)
	out, err := c.Output()
	if err != nil {
		return nil, errors.New("Windows 작업 또는 포트 조회에 실패했습니다. 관리자 권한과 작업 상태를 확인해 주세요")
	}
	return bytes.TrimPrefix(out, []byte{0xef, 0xbb, 0xbf}), nil
}

func instanceProxyObserve(p ManagedInstance) (instanceProxyTask, error) {
	var state instanceProxyTask
	target, err := instanceProxyTarget(p)
	if err != nil {
		return state, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	// These are all read-only observations. Enumerate first to avoid wildcard task-name matching.
	const script = `$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$tasks=@(Get-ScheduledTask | Where-Object { $_.TaskName -ceq $env:GSC_PROXY_TASK })
if($tasks.Count -ne 1){ @{count=$tasks.Count} | ConvertTo-Json -Compress; exit 0 }
$t=$tasks[0]
$info=Get-ScheduledTaskInfo -InputObject $t
$actions=@($t.Actions)
$tcp=@(Get-NetTCPConnection | Where-Object {$_.RemotePort -eq 0})
$udp=@(Get-NetUDPEndpoint)
@{count=1;name=$t.TaskName;path=$t.TaskPath;state=[string]$t.State;enabled=[bool]$t.Settings.Enabled;
directory=[string]$actions[0].WorkingDirectory;executable=[string]$actions[0].Execute;arguments=[string]$actions[0].Arguments;
principal=[string]$t.Principal.UserId;actions=$actions.Count;last_result=[long]$info.LastTaskResult;
tcp_busy=(@($tcp | Where-Object {$_.LocalPort -eq [int]$env:GSC_PROXY_TCP}).Count -gt 0);
udp_busy=(@($udp | Where-Object {$_.LocalPort -eq [int]$env:GSC_PROXY_UDP}).Count -gt 0);
bridge_busy=(@($tcp | Where-Object {$_.LocalPort -eq [int]$env:GSC_PROXY_BRIDGE}).Count -gt 0)} | ConvertTo-Json -Compress`
	out, err := instanceProxyPowershell(ctx, script, []string{
		"GSC_PROXY_TASK=" + p.TaskName, "GSC_PROXY_TCP=" + strconv.Itoa(target.PublicJava),
		"GSC_PROXY_UDP=" + strconv.Itoa(target.PublicBedrock), "GSC_PROXY_BRIDGE=" + strconv.Itoa(p.BridgePort),
	})
	if err != nil {
		return state, err
	}
	if json.Unmarshal(out, &state) != nil {
		return state, errors.New("Windows 작업 상태 응답을 해석하지 못했습니다")
	}
	if err = instanceProxyValidateTask(p, state); err != nil {
		return state, err
	}
	return state, nil
}

func instanceProxyValidateTask(p ManagedInstance, s instanceProxyTask) error {
	if s.Count != 1 || s.Name != p.TaskName || s.Path != `\` || s.Actions != 1 ||
		!instanceProxySameDir(s.Directory, p.Dir) || !filepath.IsAbs(s.Executable) ||
		!strings.EqualFold(filepath.Base(s.Executable), "java.exe") ||
		!(strings.EqualFold(s.Principal, "SYSTEM") || s.Principal == "S-1-5-18") {
		return errors.New("작업의 실행 주체·Java·작업 폴더가 선택한 Velocity와 일치하지 않아 제어를 중단했습니다")
	}
	matches := instanceProxyJarPattern.FindAllStringSubmatch(s.Arguments, -1)
	if len(matches) != 1 {
		return errors.New("작업의 Velocity JAR 실행 인수를 확인할 수 없습니다")
	}
	jar := matches[0][1]
	if jar == "" {
		jar = matches[0][2]
	}
	if !filepath.IsAbs(jar) {
		jar = filepath.Join(p.Dir, jar)
	}
	if !instanceProxySameDir(jar, filepath.Join(p.Dir, "velocity.jar")) {
		return errors.New("작업이 선택한 폴더의 velocity.jar를 실행하지 않습니다")
	}
	return nil
}

func (s instanceProxyTask) stopped() bool {
	// A failed task can look Ready while a delayed RestartOnFailure retry is pending.
	// 267011 is SCHED_S_TASK_HAS_NOT_RUN and is safe for first startup.
	quiet := s.State == "Disabled" || (s.State == "Ready" && (s.LastResult == 0 || s.LastResult == 267011))
	return quiet && !s.TCPBusy && !s.UDPBusy && !s.BridgeBusy
}

func instanceProxySecretPath(p ManagedInstance) string {
	return filepath.Join(filepath.Dir(configPath), "instance-secrets", p.ID+".json")
}

func instanceProxyReadSecret(p ManagedInstance) (instanceProxySecret, error) {
	var s instanceProxySecret
	if !instanceProxyIDPattern.MatchString(p.ID) {
		return s, errors.New("올바르지 않은 프록시 ID입니다")
	}
	b, err := os.ReadFile(instanceProxySecretPath(p))
	if err != nil || len(b) > 8192 || json.Unmarshal(b, &s) != nil || s.ID != p.ID ||
		!instanceProxySameDir(s.Directory, p.Dir) || s.Port != p.BridgePort || len(s.Token) != 64 {
		return s, errors.New("로컬 제어 연결이 준비되지 않았습니다. 프록시를 정상 종료한 뒤 연결 준비를 눌러 주세요")
	}
	if raw, e := hex.DecodeString(s.Token); e != nil || len(raw) != 32 {
		return instanceProxySecret{}, errors.New("로컬 제어 인증 파일이 올바르지 않습니다")
	}
	return s, nil
}

func instanceProxyPrepared(p ManagedInstance) error {
	s, err := instanceProxyReadSecret(p)
	if err != nil {
		return err
	}
	props := []byte(fmt.Sprintf("# GSC local-only control. Do not share this file.\nport=%d\ntoken=%s\n", s.Port, s.Token))
	for path, want := range map[string][]byte{
		filepath.Join(p.Dir, "plugins", "gscvelocitycontrol", "control.properties"): props,
		filepath.Join(p.Dir, "plugins", "gsc-velocity-control.jar"):                 instanceProxyPlugin,
	} {
		got, e := os.ReadFile(path)
		if e != nil || !bytes.Equal(got, want) {
			return errors.New("연결 플러그인 또는 설정이 준비되지 않았거나 변경됐습니다. 중지 상태에서 연결 준비를 확인해 주세요")
		}
	}
	return nil
}

func instanceProxyHTTP(p ManagedInstance, method, path string, expected *instanceProxyBridge) (*http.Response, error) {
	s, err := instanceProxyReadSecret(p)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	// Response body is small and consumed here so cancelling cannot race the caller's read.
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, method, "http://127.0.0.1:"+strconv.Itoa(s.Port)+path, nil)
	req.Header.Set("Authorization", "Bearer "+s.Token)
	if expected != nil {
		req.Header.Set("X-GSC-Expected-PID", strconv.Itoa(expected.PID))
		req.Header.Set("X-GSC-Expected-Start", strconv.FormatInt(expected.StartTime, 10))
	}
	transport := &http.Transport{Proxy: nil, DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Do(req)
	if err != nil {
		return nil, errors.New("Velocity 로컬 제어에 연결할 수 없습니다. 플러그인 설치 및 프록시 실행 상태를 확인해 주세요")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 8193))
	resp.Body.Close()
	if err != nil || len(b) > 8192 {
		return nil, errors.New("Velocity 로컬 제어 응답이 올바르지 않습니다")
	}
	resp.Body = io.NopCloser(bytes.NewReader(b))
	return resp, nil
}

func instanceProxyReadBridge(p ManagedInstance) (instanceProxyBridge, error) {
	var s instanceProxyBridge
	resp, err := instanceProxyHTTP(p, http.MethodGet, "/status", nil)
	if err != nil {
		return s, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK || json.NewDecoder(resp.Body).Decode(&s) != nil || s.PID <= 0 ||
		s.StartTime <= 0 || s.Players < 0 || s.JavaPort != p.JavaPort || !instanceProxySameDir(s.Directory, p.Dir) {
		return s, errors.New("로컬 제어 응답의 프록시 경로·포트·인증이 일치하지 않습니다")
	}
	return s, nil
}

func instanceProxyStatus(p ManagedInstance) InstanceStatus {
	s := InstanceStatus{ManagedInstance: p, Status: "error", Players: -1, Owner: "Windows Scheduled Tasks"}
	if _, err := instanceProxyTarget(p); err != nil {
		s.Message = err.Error()
		return s
	}
	if b, err := instanceProxyReadBridge(p); err == nil {
		s.Status, s.PID, s.Players = "online", b.PID, b.Players
		s.CanStop = b.Players == 0 && !b.Stopping
		s.Message = "로컬 제어 연결됨 · 기존 Windows 작업이 실행을 관리합니다"
		if b.Players > 0 {
			s.Message = "접속자가 있어 정상 종료·재시작을 잠갔습니다"
		}
		if b.Stopping {
			s.Status, s.Message = "stopping", "정상 종료 중입니다"
		}
		return s
	}
	task, err := instanceProxyObserve(p)
	if err != nil {
		s.Message = err.Error()
		return s
	}
	if task.stopped() {
		s.Status = "offline"
		s.CanStart = task.Enabled && task.State == "Ready" && instanceProxyPrepared(p) == nil
		s.Message = "중지됨 · 연결 준비 후 시작하면 정상 종료 기능을 사용할 수 있습니다"
		if !task.Enabled {
			s.Message = "Windows 작업이 비활성화되어 있습니다. 이 화면은 작업 설정을 변경하지 않습니다"
		}
	} else {
		s.Status = "external"
		s.Message = "기존 프록시가 실행 중이거나 포트를 사용 중입니다. 로컬 제어 연결 준비에는 먼저 정상 종료가 필요합니다"
	}
	return s
}

func instanceProxyAction(p ManagedInstance, action string) error {
	if _, err := instanceProxyTarget(p); err != nil {
		return err
	}
	switch action {
	case "start":
		return instanceProxyStart(p)
	case "stop":
		return instanceProxyStop(p)
	case "restart":
		if err := instanceProxyStop(p); err != nil {
			return err
		}
		return instanceProxyStart(p)
	case "prepare-bridge":
		return instanceProxyPrepare(p)
	default:
		return errors.New("지원하지 않는 프록시 작업입니다")
	}
}

func instanceProxyStart(p ManagedInstance) error {
	if err := instanceProxyPrepared(p); err != nil {
		return err
	}
	s, err := instanceProxyObserve(p)
	if err != nil {
		return err
	}
	if !s.stopped() || !s.Enabled || s.State != "Ready" {
		return errors.New("작업이 실행 가능 상태가 아니거나 프록시 포트가 사용 중입니다. 중복 실행을 방지했습니다")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	c := exec.CommandContext(ctx, "schtasks.exe", "/Run", "/TN", `\`+p.TaskName)
	hideProcess(c)
	if err := c.Run(); err != nil {
		return errors.New("기존 Windows 작업의 시작 요청이 실패했습니다")
	}
	deadline := time.Now().Add(45 * time.Second)
	for time.Now().Before(deadline) {
		if b, e := instanceProxyReadBridge(p); e == nil && !b.Stopping {
			conn, e := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(p.JavaPort)), time.Second)
			if e == nil {
				conn.Close()
				return nil
			}
		}
		time.Sleep(time.Second)
	}
	return errors.New("시작 요청은 전달됐지만 45초 안에 로컬 제어와 Java 포트 응답을 확인하지 못했습니다. 로그를 확인해 주세요. 재실행하거나 강제 종료하지 않았습니다")
}

func instanceProxyStop(p ManagedInstance) error {
	if _, err := instanceProxyObserve(p); err != nil {
		return err
	}
	b, err := instanceProxyReadBridge(p)
	if err != nil {
		return err
	}
	if b.Players != 0 {
		return errors.New("접속자가 있어 종료하지 않았습니다. 모두 나간 뒤 다시 시도해 주세요")
	}
	watch, err := watchPID(b.PID)
	if err != nil {
		return errors.New("실제 프록시 프로세스의 종료를 확인할 수 없어 요청하지 않았습니다")
	}
	defer watch.close()
	resp, err := instanceProxyHTTP(p, http.MethodPost, "/shutdown", &b)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		return errors.New("프록시가 종료를 거절했습니다. 접속자 또는 실행 상태가 바뀌었을 수 있습니다")
	}
	deadline := time.Now().Add(45 * time.Second)
	for time.Now().Before(deadline) {
		if !watch.alive() {
			s, e := instanceProxyObserve(p)
			if e == nil && s.stopped() {
				// A second observation catches an immediate Scheduler respawn before restart.
				time.Sleep(2 * time.Second)
				again, e := instanceProxyObserve(p)
				if e == nil && again.stopped() {
					return nil
				}
			}
		}
		time.Sleep(time.Second)
	}
	return errors.New("정상 종료 요청 후 프로세스·포트·Windows 작업의 중지를 확인하지 못했습니다. 자동 재실행 여부를 확인해 주세요. 강제 종료하거나 재시작하지 않았습니다")
}

func instanceProxyPrivateDirectory(path string) error {
	if err := instanceProxyNoLinks(path); err != nil {
		return err
	}
	if err := os.MkdirAll(path, 0700); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	// Replace only this private directory's DACL, including any old explicit broad grant.
	const script = `$ErrorActionPreference='Stop'
$acl=Get-Acl -LiteralPath $env:GSC_PRIVATE_DIRECTORY
$acl.SetSecurityDescriptorSddlForm('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)',[Security.AccessControl.AccessControlSections]::Access)
Set-Acl -LiteralPath $env:GSC_PRIVATE_DIRECTORY -AclObject $acl`
	if _, err := instanceProxyPowershell(ctx, script, []string{"GSC_PRIVATE_DIRECTORY=" + path}); err != nil {
		return errors.New("로컬 인증 폴더 보호에 실패했습니다. 관리자 권한으로 연결 준비를 실행해 주세요")
	}
	return nil
}

func instanceProxyNoLinks(path string) error {
	for path = filepath.Clean(path); ; path = filepath.Dir(path) {
		st, err := os.Lstat(path)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && st.Mode()&os.ModeSymlink != 0 {
			return errors.New("연결 준비 파일 경로에 링크·정션이 있어 변경하지 않았습니다")
		}
		if filepath.Dir(path) == path {
			return nil
		}
	}
}

func instanceProxyWriteOnce(path string, data []byte) error {
	if err := instanceProxyNoLinks(path); err != nil {
		return err
	}
	old, err := os.ReadFile(path)
	if err == nil {
		if bytes.Equal(old, data) {
			return nil
		}
		return errors.New("기존 연결 파일의 내용이 달라 덮어쓰지 않았습니다. 기존 설정을 확인해 주세요")
	}
	if !os.IsNotExist(err) {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".gsc-prepare-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	// A hard link publishes the complete file atomically and cannot replace an existing file.
	return os.Link(f.Name(), path)
}

func instanceProxyPrepare(p ManagedInstance) error {
	s, err := instanceProxyObserve(p)
	if err != nil {
		return err
	}
	if !s.stopped() {
		return errors.New("실행 중인 프록시에 설치하지 않았습니다. 기존 Velocity 콘솔에서 정상 종료한 뒤 연결 준비를 다시 눌러 주세요")
	}
	for _, name := range []string{"velocity.jar", "velocity.toml"} {
		if st, e := os.Stat(filepath.Join(p.Dir, name)); e != nil || st.IsDir() {
			return errors.New("기존 Velocity JAR 또는 설정 파일을 찾지 못했습니다")
		}
	}
	secretDir := filepath.Dir(instanceProxySecretPath(p))
	if err = instanceProxyPrivateDirectory(secretDir); err != nil {
		return err
	}
	secret, err := instanceProxyReadSecret(p)
	if err != nil {
		if _, e := os.Stat(instanceProxySecretPath(p)); !os.IsNotExist(e) {
			return err
		}
		token := make([]byte, 32)
		if _, e := rand.Read(token); e != nil {
			return e
		}
		secret = instanceProxySecret{ID: p.ID, Directory: p.Dir, Port: p.BridgePort, Token: hex.EncodeToString(token)}
		data, _ := json.Marshal(secret)
		if e := instanceProxyWriteOnce(instanceProxySecretPath(p), data); e != nil {
			return e
		}
	}
	pluginDir := filepath.Join(p.Dir, "plugins", "gscvelocitycontrol")
	if err = instanceProxyPrivateDirectory(pluginDir); err != nil {
		return err
	}
	props := []byte(fmt.Sprintf("# GSC local-only control. Do not share this file.\nport=%d\ntoken=%s\n", secret.Port, secret.Token))
	if err = instanceProxyWriteOnce(filepath.Join(pluginDir, "control.properties"), props); err != nil {
		return err
	}
	// Install the JAR last; an interrupted prepare cannot load a plugin without its credentials.
	if err = instanceProxyWriteOnce(filepath.Join(p.Dir, "plugins", "gsc-velocity-control.jar"), instanceProxyPlugin); err != nil {
		return err
	}
	return nil
}

func registerInstanceProxyRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v5/instances/proxy-candidates", requireAuth(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "GET only", http.StatusMethodNotAllowed)
			return
		}
		items := []ManagedInstance{}
		for i, t := range day11ExternalProxyTargets {
			dir := filepath.Join(externalProxyRoot(), t.ID)
			if st, err := os.Stat(filepath.Join(dir, "velocity.jar")); err != nil || st.IsDir() {
				continue
			}
			items = append(items, ManagedInstance{ID: "proxy-" + t.ID, Name: "Velocity " + t.ID, Kind: "velocity", ManagementMode: "scheduler", Dir: dir, LaunchMode: "scheduled-task", LaunchFile: "velocity.jar", JavaPort: t.PublicJava, TaskName: t.TaskName, BridgePort: 28901 + i})
		}
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		json.NewEncoder(w).Encode(map[string]any{"instances": items})
	}))
}
