package main

import (
	"context"
	"errors"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type agentActionReq struct {
	Action string `json:"action"`
}

type LaunchStatus struct {
	Phase           string `json:"phase"`
	Message         string `json:"message"`
	Error           string `json:"error,omitempty"`
	Java            string `json:"java,omitempty"`
	JavaHome        string `json:"java_home,omitempty"`
	LogPath         string `json:"log_path,omitempty"`
	PID             int    `json:"pid,omitempty"`
	ExitCode        *int   `json:"exit_code,omitempty"`
	FailureCode     string `json:"failure_code,omitempty"`
	FailureTitle    string `json:"failure_title,omitempty"`
	FailureHint     string `json:"failure_hint,omitempty"`
	FailureSource   string `json:"failure_source,omitempty"`
	FailureLine     string `json:"failure_line,omitempty"`
	FailureDetected string `json:"failure_detected,omitempty"`
	Updated         string `json:"updated"`
}
type launchProcess struct {
	cmd  *exec.Cmd
	done chan struct{}
	err  error
}

var runtimeMu sync.Mutex
var launchStates = map[string]LaunchStatus{}
var launches = map[string]*launchProcess{}
var serverProcesses = map[string]*processWatch{}
var agentDesired atomic.Bool
var activeAgent *os.Process // guarded by agentStartMu
var shuttingDown atomic.Bool
var supervisionPaused atomic.Bool
var hostQuit = make(chan struct{})
var finishShutdown = make(chan struct{}, 1)
var quitOnce sync.Once

func configSnapshot() Config {
	configMu.RLock()
	defer configMu.RUnlock()
	c := cfg
	c.Servers = append([]ServerConfig(nil), cfg.Servers...)
	return c
}
func cachedJavaStats(port int) (JavaStats, bool) {
	statusMu.Lock()
	defer statusMu.Unlock()
	v, ok := javaCache[port]
	return v, ok
}
func cachedTCPListener(port int) bool {
	statusMu.Lock()
	defer statusMu.Unlock()
	_, ok := javaCache[port]
	return ok
}
func launcherLogPath(id string) string {
	return filepath.Join(filepath.Dir(configPath), "logs", id+"-launcher.log")
}
func launchStatus(id string) LaunchStatus {
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	return launchStates[id]
}
func setLaunchPhase(id, phase, msg, errText string) {
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	v := launchStates[id]
	v.Phase = phase
	v.Message = msg
	v.Error = errText
	v.Updated = time.Now().Format(time.RFC3339)
	v.LogPath = launcherLogPath(id)
	launchStates[id] = v
}
func recordResult(id, action, msg string, e error) {
	phase := "online"
	if action == "stop" {
		phase = "stopped"
	}
	errText := ""
	if e != nil {
		phase = "error"
		errText = e.Error()
	}
	setLaunchPhase(id, phase, msg, errText)
	f, err := os.OpenFile(launcherLogPath(id), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err == nil {
		defer f.Close()
		fmt.Fprintf(f, "[%s] %s: %s %s\r\n", time.Now().Format(time.RFC3339), action, msg, errText)
	}
}
func setAgentDesired(v bool) {
	if v && shuttingDown.Load() {
		v = false
	}
	if v {
		supervisionPaused.Store(false)
	}
	agentDesired.Store(v)
}
func getAgentDesired() bool { return agentDesired.Load() }
func getLaunch(id string) *launchProcess {
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	return launches[id]
}
func launchAlive(id string) bool {
	p := getLaunch(id)
	if p == nil {
		return false
	}
	select {
	case <-p.done:
		return false
	default:
		return true
	}
}
func stopLaunchShell(id string) {
	if p := getLaunch(id); p != nil && launchAlive(id) {
		_ = p.cmd.Process.Kill()
	}
}

// forceStopLauncherTree terminates the tracked start.bat/cmd.exe process tree.
// Unlike stopLaunchShell, this intentionally kills child Java processes too.
func forceStopLauncherTree(id string) error {
	p := getLaunch(id)
	if p == nil || !launchAlive(id) || p.cmd == nil || p.cmd.Process == nil {
		return errors.New("start.bat is not running")
	}
	pid := p.cmd.Process.Pid
	if pid <= 0 {
		return errors.New("start.bat PID unavailable")
	}
	if err := killProcessTree(pid); err != nil {
		return err
	}
	appendLauncherNote(id, fmt.Sprintf("start.bat process tree force-stopped (PID %d)", pid))
	return nil
}
func trackedServerAlive(id string) bool {
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	p := serverProcesses[id]
	if p == nil {
		return false
	}
	if p.alive() {
		return true
	}
	p.close()
	delete(serverProcesses, id)
	return false
}
func trackedServerPID(id string) int {
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	p := serverProcesses[id]
	if p == nil {
		return 0
	}
	if !p.alive() {
		p.close()
		delete(serverProcesses, id)
		return 0
	}
	return p.pidValue()
}
func rememberServerProcess(s ServerConfig) error {
	if trackedServerAlive(s.ID) {
		return nil
	}
	pid, e := portPID(s.JavaPort)
	if e != nil {
		return e
	}
	p, e := watchPID(pid)
	if e != nil {
		return e
	}
	runtimeMu.Lock()
	defer runtimeMu.Unlock()
	if old := serverProcesses[s.ID]; old != nil {
		old.close()
	}
	serverProcesses[s.ID] = p
	return nil
}

// Resolve the user's existing batch inside the server directory. Both start and
// restart call this function, so they use exactly the same file and environment.
func resolveLaunch(command, dir string) (line, actual string, err error) {
	command = strings.TrimSpace(command)
	if command == "" {
		command = "start.bat"
	}
	plain := strings.Trim(command, "\"")
	ext := strings.ToLower(filepath.Ext(plain))
	if ext == ".bat" || ext == ".cmd" {
		full := plain
		if !filepath.IsAbs(full) {
			full = filepath.Join(dir, full)
		}
		if _, e := os.Stat(full); e != nil {
			if strings.EqualFold(plain, "start.bat") {
				for _, alt := range []string{"start.cmd", "run.bat", "run.cmd", "server.bat", "server.cmd"} {
					p := filepath.Join(dir, alt)
					if info, e := os.Stat(p); e == nil && !info.IsDir() {
						full = p
						break
					}
				}
			}
		}
		info, e := os.Stat(full)
		if e != nil {
			return "", "", fmt.Errorf("start.bat 실행 파일 확인 실패: %s: %w", full, e)
		}
		if info.IsDir() {
			return "", "", fmt.Errorf("배치파일 경로가 폴더입니다: %s", full)
		}
		// One expansion, no CALL second pass: paths containing percent signs remain literal.
		return `"%GSC_LAUNCH_FILE%"`, full, nil
	}
	if strings.ContainsAny(command, "\r\n\x00") {
		return "", "", errors.New("start_command에 줄바꿈이 포함되어 있습니다")
	}
	return command, "", nil
}
func runDetachedCommand(command, dir, id string) error {
	if runtime.GOOS != "windows" {
		return errors.New("Windows only")
	}
	return launchCommand(command, dir, id)
}
func launchCommand(command, dir, id string) error {
	if dir == "" {
		return errors.New("서버 작업 폴더가 없습니다")
	}
	line, actual, e := resolveLaunch(command, dir)
	if e != nil {
		return e
	}
	java, e := javaruntime.Resolve(configSnapshot().Agent.JavaPath)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(launcherLogPath(id)), 0755); e != nil {
		return e
	}
	f, e := os.OpenFile(launcherLogPath(id), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if e != nil {
		return e
	}
	c := shellCommand(line)
	c.Dir = dir
	env := os.Environ()
	env = setEnvValue(env, "JAVA_HOME", java.Home)
	env = setEnvValue(env, "PATH", filepath.Dir(java.Executable)+string(os.PathListSeparator)+envValue(env, "PATH"))
	env = setEnvValue(env, "GSC_LAUNCH_FILE", actual)
	c.Env = env
	c.Stdout = f
	c.Stderr = f // cmd syntax failures are captured too, before any batch redirection.
	fmt.Fprintf(f, "\r\n[%s] GSC v%s launcher\r\ndir=%s\r\ncommand=%s\r\njava=%s\r\njava_home=%s\r\njava_version=%s\r\n", time.Now().Format(time.RFC3339), appVersion, dir, command, java.Executable, java.Home, java.Version)
	if e = c.Start(); e != nil {
		fmt.Fprintf(f, "CreateProcess failed: %v\r\n", e)
		f.Close()
		return e
	}
	p := &launchProcess{cmd: c, done: make(chan struct{})}
	runtimeMu.Lock()
	launches[id] = p
	launchStates[id] = LaunchStatus{Phase: "starting", Message: "start.bat 실행 후 서버 응답 확인 중", Java: java.Executable, JavaHome: java.Home, LogPath: launcherLogPath(id), PID: c.Process.Pid, Updated: time.Now().Format(time.RFC3339)}
	runtimeMu.Unlock()
	go func() {
		p.err = c.Wait()
		code := c.ProcessState.ExitCode()
		fmt.Fprintf(f, "[%s] launcher exited: code=%d error=%v\r\n", time.Now().Format(time.RFC3339), code, p.err)
		f.Close()
		runtimeMu.Lock()
		v := launchStates[id]
		v.ExitCode = &code
		launchStates[id] = v
		runtimeMu.Unlock()
		close(p.done)
	}()
	return nil
}
func startServerLocked(s ServerConfig) (string, error) {
	if shuttingDown.Load() || !getDesired(s.ID) {
		return "시작 취소", errors.New("start cancelled")
	}
	if tcpOpen("127.0.0.1", s.JavaPort, 400*time.Millisecond) {
		if e := rememberServerProcess(s); e != nil {
			return "실행 중인 서버 프로세스 확인 실패", e
		}
		return s.Name + " 이미 실행 중", nil
	}
	markAttempt(s.ID)
	probe := newStartupLogCursor(s)
	if !launchAlive(s.ID) && !trackedServerAlive(s.ID) {
		dir := resolveServerDir(s)
		if dir == "" {
			return "서버 폴더를 찾지 못함", errors.New("server directory unavailable")
		}
		setLaunchPhase(s.ID, "updating", "서버 시작 전 자체 플러그인 업데이트 확인 중", "")
		ust := runPreStartUpdater(s)
		if ust.Error != "" {
			appendLauncherNote(s.ID, "pre-start updater warning: "+ust.Error)
		} else if len(ust.Applied) > 0 {
			appendLauncherNote(s.ID, "pre-start updater applied: "+strings.Join(ust.Applied, ", "))
		}
		setLaunchPhase(s.ID, "starting", "기존 start.bat 실행 준비 중", "")
		if e := runDetachedCommand(s.StartCommand, dir, s.ID); e != nil {
			return "서버 시작 실패", e
		}
	}
	deadline := time.Now().Add(150 * time.Second)
	for time.Now().Before(deadline) {
		if shuttingDown.Load() || !getDesired(s.ID) {
			return "종료 요청으로 시작 확인 취소", errors.New("start cancelled")
		}
		if failure := probe.detect(); failure != nil {
			applyStartupFailure(s.ID, failure)
			return "서버 부팅 실패 감지 · 자동 재시작 중지", fmt.Errorf("%s: %s", failure.Title, failure.Line)
		}
		if tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) {
			if e := rememberServerProcess(s); e != nil {
				return "서버 프로세스 확인 실패", e
			}
			return s.Name + " ONLINE", nil
		}
		if p := getLaunch(s.ID); p != nil {
			select {
			case <-p.done:
				if p.err != nil {
					return "start.bat 실행 실패 · 실행 로그를 확인하세요", p.err
				}
			default:
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	if failure := probe.detect(); failure != nil {
		applyStartupFailure(s.ID, failure)
		return "서버 부팅 실패 감지 · 자동 재시작 중지", fmt.Errorf("%s: %s", failure.Title, failure.Line)
	}
	return "150초 안에 서버 응답을 확인하지 못했습니다 · 실행 로그를 확인하세요", errors.New("startup timeout")
}

func agentShutdownURL(healthURL string) string {
	u, err := url.Parse(strings.TrimSpace(healthURL))
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	u.Path = "/shutdown"
	u.RawPath = ""
	u.RawQuery = ""
	u.Fragment = ""
	return u.String()
}

// requestAgentGracefulShutdown asks Agent 0.5+ to release Discord Gateway,
// HTTP listeners and executors itself. It is deliberately best-effort: old
// Agents do not expose /shutdown, so verified PID termination remains fallback.
func requestAgentGracefulShutdown(healthURL string) bool {
	u := agentShutdownURL(healthURL)
	if u == "" {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 1400*time.Millisecond)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, strings.NewReader("{}"))
	if err != nil {
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	_ = resp.Body.Close()
	return resp.StatusCode == http.StatusAccepted || resp.StatusCode == http.StatusOK
}

func waitAgentOffline(healthURL string, timeout time.Duration) bool {
	if strings.TrimSpace(healthURL) == "" {
		return false
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, ok := getTextURL(healthURL); !ok {
			return true
		}
		time.Sleep(120 * time.Millisecond)
	}
	_, ok := getTextURL(healthURL)
	return !ok
}

func stopAgentLocked() error {
	c := configSnapshot()
	work := strings.TrimSpace(c.Agent.WorkingDir)
	if work == "" {
		return nil
	}

	// Prefer a clean Agent shutdown. This prevents an abrupt JVM kill while the
	// Discord Gateway or HTTP requests are still active. On an old/unresponsive
	// Agent the verified PID path below remains the deterministic fallback.
	if requestAgentGracefulShutdown(c.Agent.HealthURL) && waitAgentOffline(c.Agent.HealthURL, 5*time.Second) {
		activeAgent = nil
		_ = os.Remove(filepath.Join(work, "agent.pid"))
		return nil
	}

	if activeAgent != nil {
		e := activeAgent.Kill()
		activeAgent = nil
		if e != nil && !errors.Is(e, os.ErrProcessDone) {
			return e
		}
	} else if b, e := os.ReadFile(filepath.Join(work, "agent.pid")); e == nil {
		pid, e := strconv.Atoi(strings.TrimSpace(string(b)))
		if e != nil || pid <= 0 {
			return errors.New("Agent PID 파일이 잘못되었습니다")
		}
		jar := c.Agent.JarName
		if jar == "" {
			jar = "GeumyiStatusAgent-0.5.4.jar"
		}
		pattern := strings.ReplaceAll(regexp.QuoteMeta(filepath.Base(jar)), "'", "''")
		ps := fmt.Sprintf(`$ErrorActionPreference='Stop';$p=Get-CimInstance Win32_Process -Filter 'ProcessId=%d';if($p){if(($p.Name -notin @('java.exe','javaw.exe')) -or ($p.CommandLine -notmatch '%s')){throw 'Agent PID identity mismatch'};Stop-Process -Id $p.ProcessId -Force}`, pid, pattern)
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps)
		hideProcess(cmd)
		if out, e := cmd.CombinedOutput(); e != nil {
			return fmt.Errorf("Agent 종료 실패: %w %s", e, strings.TrimSpace(string(out)))
		}
	}
	_ = os.Remove(filepath.Join(work, "agent.pid"))
	return nil
}

type ShutdownStatus struct {
	Phase   string   `json:"phase"`
	Message string   `json:"message"`
	Errors  []string `json:"errors,omitempty"`
}

var shutdownMu sync.Mutex
var shutdownState = ShutdownStatus{Phase: "idle"}

func shutdownStatus() ShutdownStatus {
	shutdownMu.Lock()
	defer shutdownMu.Unlock()
	s := shutdownState
	s.Errors = append([]string(nil), s.Errors...)
	return s
}
func setShutdownState(phase, msg string, errs []string) {
	shutdownMu.Lock()
	shutdownState = ShutdownStatus{phase, msg, errs}
	shutdownMu.Unlock()
}
func apiShutdown(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "JSON required", 415)
		return
	}
	if shuttingDown.CompareAndSwap(false, true) {
		supervisionPaused.Store(true)
		setAgentDesired(false)
		for _, s := range configSnapshot().Servers {
			setDesired(s.ID, false)
		}
		setShutdownState("stopping", "서버 저장 및 정상 종료 중", nil)
		go shutdownAll()
	}
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, shutdownStatus())
}
func apiShutdownStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "GET required", 405)
		return
	}
	writeJSON(w, shutdownStatus())
}
func apiShutdownFinish(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	if shutdownStatus().Phase != "ready" {
		http.Error(w, "종료 준비가 끝나지 않았습니다", 409)
		return
	}
	writeJSON(w, map[string]any{"ok": true})
	select {
	case finishShutdown <- struct{}{}:
	default:
	}
}

// Dependencies are explicit so failure/ordering behavior is integration-testable.
func stopManagedComponents(servers []ServerConfig, stop func(ServerConfig) (string, error), agent func() error) []string {
	errs := make(chan string, len(servers))
	var wg sync.WaitGroup
	for _, s := range servers {
		wg.Add(1)
		go func(s ServerConfig) {
			defer wg.Done()
			if msg, e := stop(s); e != nil {
				errs <- s.Name + ": " + msg + " (" + e.Error() + ")"
			}
		}(s)
	}
	wg.Wait()
	close(errs)
	var failures []string
	for e := range errs {
		failures = append(failures, e)
	}
	if len(failures) > 0 {
		return failures
	}
	if e := agent(); e != nil {
		return []string{"Agent: " + e.Error()}
	}
	return nil
}
func shutdownAll() {
	failures := stopManagedComponents(configSnapshot().Servers, stopServer, stopAgent)
	if len(failures) > 0 {
		setShutdownState("failed", "전체 종료를 완료하지 못했습니다. 서버 로그를 확인해 주세요", failures)
		shuttingDown.Store(false)
		return
	}
	c := configSnapshot()
	if c.Agent.HealthURL != "" {
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			if _, ok := getTextURL(c.Agent.HealthURL); !ok {
				break
			}
			time.Sleep(250 * time.Millisecond)
		}
		if _, ok := getTextURL(c.Agent.HealthURL); ok {
			setShutdownState("failed", "Agent가 아직 실행 중입니다", []string{"Agent 종료 확인 실패"})
			shuttingDown.Store(false)
			return
		}
	}
	setShutdownState("ready", "서버와 Agent 종료 완료 · Host 종료 중", nil)
	select {
	case <-finishShutdown:
	case <-time.After(15 * time.Second):
	}
	time.Sleep(300 * time.Millisecond)
	quitOnce.Do(func() { close(hostQuit) })
}
