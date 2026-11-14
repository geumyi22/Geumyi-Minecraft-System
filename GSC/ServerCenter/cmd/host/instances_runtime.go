package main

import (
	"bytes"
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
	"sync"
	"time"
)

type instanceProcess struct {
	cmd     *exec.Cmd
	stdin   io.WriteCloser
	done    chan struct{}
	writeMu sync.Mutex
	err     error // published before done closes
}
type instanceRuntimeState struct {
	process *instanceProcess
	busy    bool
	action  string
	message string
	err     string
	log     []byte
}

var instanceRuntimeMu sync.Mutex
var instanceRuntimes = map[string]*instanceRuntimeState{}
var instanceStopTimeout = 180 * time.Second

func instanceRuntimeLocked(id string) *instanceRuntimeState {
	s := instanceRuntimes[id]
	if s == nil {
		s = &instanceRuntimeState{}
		instanceRuntimes[id] = s
	}
	return s
}
func beginInstanceOperation(id, action string) bool {
	instanceRuntimeMu.Lock()
	defer instanceRuntimeMu.Unlock()
	// Checked while claiming the operation: a request can pass its HTTP auth
	// guard immediately before apiShutdown claims the shutdown flag.
	if shuttingDown.Load() {
		return false
	}
	s := instanceRuntimeLocked(id)
	if s.busy {
		return false
	}
	s.busy = true
	s.action = action
	s.err = ""
	return true
}
func endInstanceOperation(id string, err error) {
	instanceRuntimeMu.Lock()
	defer instanceRuntimeMu.Unlock()
	s := instanceRuntimeLocked(id)
	s.busy = false
	s.action = ""
	if err != nil {
		s.err = err.Error()
		s.message = err.Error()
	}
}
func instanceMessage(id, message string) {
	instanceRuntimeMu.Lock()
	defer instanceRuntimeMu.Unlock()
	instanceRuntimeLocked(id).message = message
}
func instanceProcessAlive(p *instanceProcess) bool {
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
func instancePortOpen(port int) bool {
	if port <= 0 {
		return false
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 200*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

type instanceLogWriter struct{ id string }

func (w instanceLogWriter) Write(b []byte) (int, error) {
	instanceRuntimeMu.Lock()
	defer instanceRuntimeMu.Unlock()
	s := instanceRuntimeLocked(w.id)
	s.log = append(s.log, b...)
	if len(s.log) > 128<<10 {
		s.log = append([]byte(nil), s.log[len(s.log)-(128<<10):]...)
	}
	return len(b), nil
}

func managedInstanceStatus(p ManagedInstance) InstanceStatus {
	var out InstanceStatus
	if isScheduledProxy(p) {
		out = instanceProxyStatus(p)
	} else {
		out = InstanceStatus{ManagedInstance: p, Status: "offline", Message: "중지됨", Players: -1, CanStart: true, Owner: "gsc"}
		instanceRuntimeMu.Lock()
		s := instanceRuntimeLocked(p.ID)
		proc := s.process
		msg, lastErr := s.message, s.err
		instanceRuntimeMu.Unlock()
		alive := instanceProcessAlive(proc)
		open := instancePortOpen(p.JavaPort)
		if alive {
			out.PID = proc.cmd.Process.Pid
			out.CanStart = false
			out.CanStop = true
			out.Status = "starting"
			out.Message = "실행 중 · 서버 응답 대기"
			if open {
				mc := queryMinecraft("127.0.0.1", p.JavaPort)
				if mc.OK {
					out.Status = "online"
					out.Message = "서버 실행 중"
				} else {
					out.Message = "서버 실행 중 · Minecraft 상태 응답 대기"
					if p.Kind == "velocity" {
						out.Message = "프록시 실행 중 · Minecraft 상태 응답 대기"
					}
				}
				if mc.OK {
					out.Players = mc.Online
				}
			}
		} else if blocked, reason := instanceReceiptBlocks(p); blocked {
			out.Status = "external"
			out.Message = reason
			out.Owner = "previous_host"
			out.CanStart = false
		} else if open {
			out.Status = "external"
			out.Message = "GSC 밖에서 실행 중입니다. 기존 콘솔에서 종료한 뒤 시작하세요"
			out.Owner = "external"
			out.CanStart = false
		} else if lastErr != "" {
			out.Status = "error"
			out.Message = lastErr
		} else if msg != "" {
			out.Message = msg
		}
	}
	instanceRuntimeMu.Lock()
	s := instanceRuntimeLocked(p.ID)
	busy, action, msg, lastErr := s.busy, s.action, s.message, s.err
	instanceRuntimeMu.Unlock()
	out.Busy = busy
	if busy {
		out.CanStart = false
		out.CanStop = false
		if action == "stop" || action == "restart" {
			out.Status = "stopping"
		}
		if action == "start" {
			out.Status = "starting"
		}
		if msg != "" {
			out.Message = msg
		}
	}
	if !busy && lastErr != "" {
		out.Message = lastErr
		if out.Status == "offline" {
			out.Status = "error"
		}
	}
	return out
}

func verifyInstanceFiles(p ManagedInstance) error {
	st, err := os.Stat(p.Dir)
	if err != nil || !st.IsDir() {
		return errors.New("서버 폴더를 찾지 못했습니다")
	}
	resolved, err := canonicalInstanceDir(p.Dir)
	if err != nil {
		return err
	}
	if !strings.EqualFold(resolved, p.Dir) {
		return errors.New("서버 폴더의 실제 경로가 변경되었습니다. 다시 등록하세요")
	}
	if p.Kind == "velocity" {
		if _, err = os.Stat(filepath.Join(p.Dir, "velocity.toml")); err != nil {
			return errors.New("Velocity 폴더에 velocity.toml이 없습니다")
		}
		if isScheduledProxy(p) {
			return nil
		}
	}
	file := filepath.Join(p.Dir, p.LaunchFile)
	resolvedFile, err := filepath.EvalSymlinks(file)
	if err != nil {
		return fmt.Errorf("실행 파일을 찾지 못했습니다: %w", err)
	}
	rel, err := filepath.Rel(p.Dir, resolvedFile)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return errors.New("실행 파일이 서버 폴더 밖을 가리킵니다")
	}
	st, err = os.Stat(resolvedFile)
	if err != nil || !st.Mode().IsRegular() {
		return errors.New("일반 실행 파일을 선택하세요")
	}
	if p.Kind == "velocity" {
		return verifyManagedVelocityBind(p)
	}
	if b, err := os.ReadFile(filepath.Join(p.Dir, "server.properties")); err == nil {
		port := 25565
		for _, line := range strings.Split(string(b), "\n") {
			k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
			if ok && strings.TrimSpace(k) == "server-port" {
				n, e := strconv.Atoi(strings.TrimSpace(v))
				if e != nil {
					return errors.New("server.properties의 server-port가 올바르지 않습니다")
				}
				port = n
			}
		}
		if port != p.JavaPort {
			return fmt.Errorf("등록 포트 %d와 server.properties의 포트 %d가 다릅니다. 파일을 변경하지 않았습니다", p.JavaPort, port)
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	return nil
}

func verifyManagedVelocityBind(p ManagedInstance) error {
	b, err := os.ReadFile(filepath.Join(p.Dir, "velocity.toml"))
	if err != nil {
		return err
	}
	// Velocity's root bind precedes TOML tables. Do not confuse nested plugin
	// settings or backend addresses with the proxy's own listener.
	for _, raw := range strings.Split(string(b), "\n") {
		line := strings.TrimSpace(strings.TrimPrefix(raw, "\ufeff"))
		if strings.HasPrefix(line, "[") {
			break
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(key) != "bind" {
			continue
		}
		value = strings.TrimSpace(value)
		if len(value) < 2 || (value[0] != '"' && value[0] != '\'') {
			return errors.New("velocity.toml의 bind 주소를 확인하세요")
		}
		end := strings.IndexByte(value[1:], value[0])
		if end < 0 {
			return errors.New("velocity.toml의 bind 주소를 확인하세요")
		}
		_, portText, err := net.SplitHostPort(value[1 : end+1])
		port, parseErr := strconv.Atoi(portText)
		if err != nil || parseErr != nil || port != p.JavaPort {
			return fmt.Errorf("등록 포트 %d와 velocity.toml의 bind 포트가 다릅니다. 파일을 변경하지 않았습니다", p.JavaPort)
		}
		return nil
	}
	return errors.New("velocity.toml에서 bind 포트를 찾지 못했습니다")
}

func instanceJavaExecutable(p ManagedInstance) (string, error) {
	if p.JavaPath != "" {
		st, err := os.Stat(p.JavaPath)
		if err != nil || st.IsDir() {
			return "", errors.New("선택한 Java 실행 파일을 찾지 못했습니다")
		}
		return p.JavaPath, nil
	}
	x, err := exec.LookPath("java")
	if err != nil {
		return "", errors.New("Java를 찾지 못했습니다. Java 실행 파일을 선택하세요")
	}
	return x, nil
}

var generatedArgsPattern = regexp.MustCompile(`(?i)@((?:libraries[/\\])[^\s"']+(?:win|unix)_args\.txt)`)

func instanceJavaUTF8Args() []string {
	// Host log transport is UTF-8. Windows Java otherwise may encode redirected
	// Korean output with the system code page, including on recent JDK releases.
	return []string{"-Dfile.encoding=UTF-8", "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-Dsun.stdout.encoding=UTF-8", "-Dsun.stderr.encoding=UTF-8"}
}

// The generated Forge/NeoForge argument files preserve loader setup, while
// launching Java directly gives GSC ownership of stdin and the actual JVM.
func instanceLaunchCommand(p ManagedInstance) (*exec.Cmd, error) {
	java, err := instanceJavaExecutable(p)
	if err != nil {
		return nil, err
	}
	var cmd *exec.Cmd
	if p.LaunchMode == "jar" {
		args := append(instanceJavaUTF8Args(), fmt.Sprintf("-Xmx%dM", p.MemoryMB), "-jar", filepath.Join(p.Dir, p.LaunchFile), "nogui")
		cmd = exec.Command(java, args...)
	} else {
		b, err := os.ReadFile(filepath.Join(p.Dir, p.LaunchFile))
		if err != nil {
			return nil, err
		}
		if len(b) > 128<<10 {
			return nil, errors.New("실행 스크립트가 너무 큽니다")
		}
		argsFile := ""
		if p.Kind == "forge" || p.Kind == "neoforge" {
			if m := generatedArgsPattern.FindSubmatch(b); len(m) > 1 {
				argsFile = string(m[1])
			}
		}
		if argsFile != "" {
			resolved, err := filepath.EvalSymlinks(filepath.Join(p.Dir, filepath.FromSlash(argsFile)))
			if err != nil {
				return nil, err
			}
			rel, _ := filepath.Rel(p.Dir, resolved)
			if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
				return nil, errors.New("로더 인수 파일이 서버 폴더를 벗어납니다")
			}
			args := []string{}
			if _, err := os.Stat(filepath.Join(p.Dir, "user_jvm_args.txt")); err == nil {
				args = append(args, "@user_jvm_args.txt")
			}
			args = append(args, instanceJavaUTF8Args()...)
			args = append(args, fmt.Sprintf("-Xmx%dM", p.MemoryMB), "@"+argsFile, "nogui")
			cmd = exec.Command(java, args...)
		} else {
			lower := strings.ToLower(string(b))
			for _, line := range strings.Split(lower, "\n") {
				line = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "@"))
				if strings.HasPrefix(line, "goto ") || strings.HasPrefix(line, "start ") {
					return nil, errors.New("자동 반복 또는 분리 실행 스크립트입니다. JVM을 직접 실행하는 스크립트를 선택하세요")
				}
			}
			if runtime.GOOS == "windows" {
				if strings.ContainsAny(p.Dir, "\"%!\r\n") {
					return nil, errors.New("실행 폴더에 스크립트가 해석할 특수 문자가 있습니다")
				}
				cmd = shellCommand(`"` + filepath.Join(p.Dir, p.LaunchFile) + `"`)
			} else {
				cmd = exec.Command("sh", filepath.Join(p.Dir, p.LaunchFile))
			}
		}
	}
	cmd.Dir = p.Dir
	// Explicit Java selection also applies to generated scripts using bare java.
	javaBin := filepath.Dir(java)
	javaHome := filepath.Dir(javaBin)
	env := []string{}
	for _, v := range os.Environ() {
		key, _, _ := strings.Cut(v, "=")
		if !strings.EqualFold(key, "PATH") && !strings.EqualFold(key, "JAVA_HOME") {
			env = append(env, v)
		}
	}
	cmd.Env = append(env, "JAVA_HOME="+javaHome, "PATH="+javaBin+string(os.PathListSeparator)+os.Getenv("PATH"))
	hideProcess(cmd)
	return cmd, nil
}

func checkInstanceLaunchCollision(p ManagedInstance) error {
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		return err
	}
	others := make([]ManagedInstance, 0, len(profiles))
	for _, v := range profiles {
		if v.ID != p.ID {
			others = append(others, v)
		}
	}
	return validateInstanceAgainst(p, others)
}

func startManagedInstance(p ManagedInstance) error {
	if err := verifyInstanceFiles(p); err != nil {
		return err
	}
	if err := checkInstanceLaunchCollision(p); err != nil {
		return err
	}
	instanceRuntimeMu.Lock()
	proc := instanceRuntimeLocked(p.ID).process
	instanceRuntimeMu.Unlock()
	if instanceProcessAlive(proc) {
		return errors.New("이미 실행 중입니다")
	}
	if blocked, reason := instanceReceiptBlocks(p); blocked {
		return errors.New(reason)
	}
	if instancePortOpen(p.JavaPort) {
		return errors.New("접속 포트를 다른 프로세스가 사용 중입니다")
	}
	cmd, err := instanceLaunchCommand(p)
	if err != nil {
		return err
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	writer := instanceLogWriter{id: p.ID}
	cmd.Stdout = writer
	cmd.Stderr = writer
	proc = &instanceProcess{cmd: cmd, stdin: stdin, done: make(chan struct{})}
	receipt, err := prepareInstanceReceipt(p)
	if err != nil {
		_ = stdin.Close()
		return fmt.Errorf("실행 확인 기록을 저장하지 못해 시작하지 않았습니다: %w", err)
	}
	if err = cmd.Start(); err != nil {
		_ = stdin.Close()
		clearInstanceReceipt(p, receipt)
		return err
	}
	instanceRuntimeMu.Lock()
	s := instanceRuntimeLocked(p.ID)
	s.process = proc
	s.err = ""
	s.message = "프로세스를 시작했습니다. 서버 응답을 기다립니다"
	instanceRuntimeMu.Unlock()
	receipt.State = "running"
	receipt.PID = cmd.Process.Pid
	_, receipt.ProcessCreated, err = instanceProcessIdentity(receipt.PID)
	if err == nil {
		err = writeInstanceReceipt(p, receipt)
	}
	if err != nil {
		instanceRuntimeMu.Lock()
		s.err = "서버는 실행 중이나 실행 기록 저장에 실패했습니다. Host를 종료하기 전에 서버를 정상 종료하세요"
		instanceRuntimeMu.Unlock()
	}
	go func() {
		proc.err = cmd.Wait()
		_ = stdin.Close()
		clearInstanceReceipt(p, receipt)
		close(proc.done)
		instanceRuntimeMu.Lock()
		defer instanceRuntimeMu.Unlock()
		s := instanceRuntimeLocked(p.ID)
		if s.process != proc {
			return
		}
		if proc.err != nil {
			s.err = "서버가 종료되었습니다: " + proc.err.Error()
			s.message = s.err
		} else {
			s.message = "서버가 정상 종료되었습니다"
		}
	}()
	return nil
}

func stopManagedInstance(p ManagedInstance) error {
	instanceRuntimeMu.Lock()
	proc := instanceRuntimeLocked(p.ID).process
	instanceRuntimeMu.Unlock()
	if !instanceProcessAlive(proc) {
		if blocked, reason := instanceReceiptBlocks(p); blocked {
			return errors.New(reason)
		}
		if instancePortOpen(p.JavaPort) {
			return errors.New("GSC가 실행한 프로세스가 아닙니다. 기존 콘솔에서 종료하세요")
		}
		return nil
	}
	instanceMessage(p.ID, "정상 종료 명령 전송 · 저장 및 프로세스 종료 대기")
	command := "stop\n"
	if p.Kind == "velocity" {
		command = "shutdown\n"
		instanceMessage(p.ID, "프록시 정상 종료 명령 전송 · 연결 정리 및 프로세스 종료 대기")
	}
	proc.writeMu.Lock()
	_, err := io.WriteString(proc.stdin, command)
	_ = proc.stdin.Close()
	proc.writeMu.Unlock()
	if err != nil {
		return fmt.Errorf("종료 명령 전송 실패: %w", err)
	}
	select {
	case <-proc.done:
	case <-time.After(instanceStopTimeout):
		return errors.New("정상 종료 대기 시간이 지났습니다. 강제 종료하지 않았습니다. 콘솔을 확인하세요")
	}
	if proc.err != nil {
		return fmt.Errorf("종료 중 프로세스 오류가 발생했습니다. 재시작을 중단했습니다: %w", proc.err)
	}
	if instancePortOpen(p.JavaPort) {
		return errors.New("프로세스 종료 후에도 포트가 사용 중입니다. 재시작을 중단했습니다")
	}
	instanceMessage(p.ID, "서버 종료를 확인했습니다")
	return nil
}

func runManagedInstanceAction(p ManagedInstance, action string) error {
	if isScheduledProxy(p) {
		return instanceProxyAction(p, action)
	}
	switch action {
	case "start":
		return startManagedInstance(p)
	case "stop":
		return stopManagedInstance(p)
	case "restart":
		if err := stopManagedInstance(p); err != nil {
			return err
		}
		return startManagedInstance(p)
	default:
		return errors.New("지원하지 않는 작업입니다")
	}
}

func apiInstanceAction(w http.ResponseWriter, r *http.Request) {
	var q struct {
		ID     string `json:"id"`
		Action string `json:"action"`
	}
	if !decodeInstanceRequest(w, r, &q) {
		return
	}
	if q.Action != "start" && q.Action != "stop" && q.Action != "restart" {
		http.Error(w, "지원하지 않는 작업입니다", 400)
		return
	}
	p, err := instanceByID(q.ID)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	if !beginInstanceOperation(p.ID, q.Action) {
		http.Error(w, "이미 작업이 진행 중입니다", 409)
		return
	}
	instanceMessage(p.ID, map[string]string{"start": "시작 요청 처리 중", "stop": "정상 종료 요청 처리 중", "restart": "정상 종료 후 재시작 중"}[q.Action])
	appendAudit(r, "instance."+q.Action, p.ID, "accepted", "manual operation")
	go func() {
		err := runManagedInstanceAction(p, q.Action)
		endInstanceOperation(p.ID, err)
		result := "ok"
		detail := ""
		if err != nil {
			result = "failed"
			detail = err.Error()
		}
		appendV4Event(result, "instance", p.ID, q.Action, detail)
	}()
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]any{"ok": true, "accepted": true, "message": "요청을 접수했습니다. 완료 상태는 서버 카드에서 확인하세요."})
}

func apiInstancePrepare(w http.ResponseWriter, r *http.Request) {
	var q struct {
		ID string `json:"id"`
	}
	if !decodeInstanceRequest(w, r, &q) {
		return
	}
	p, err := instanceByID(q.ID)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	if !isScheduledProxy(p) {
		http.Error(w, "기존 Scheduler 관리 Velocity 전용 작업입니다", 400)
		return
	}
	if !beginInstanceOperation(p.ID, "prepare") {
		http.Error(w, "작업이 진행 중입니다", 409)
		return
	}
	go func() {
		err := instanceProxyPrepare(p)
		if err == nil {
			instanceMessage(p.ID, "정상 종료 연결 준비 완료. 다음 프록시 시작 시 적용됩니다")
		}
		endInstanceOperation(p.ID, err)
	}()
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]any{"ok": true, "accepted": true})
}

func apiInstanceCommand(w http.ResponseWriter, r *http.Request) {
	var q struct {
		ID      string `json:"id"`
		Command string `json:"command"`
	}
	if !decodeInstanceRequest(w, r, &q) {
		return
	}
	p, err := instanceByID(q.ID)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	q.Command = strings.TrimSpace(q.Command)
	if q.Command == "" || len(q.Command) > 2048 || strings.ContainsAny(q.Command, "\r\n\x00") {
		http.Error(w, "명령어 한 줄을 입력하세요", 400)
		return
	}
	if isScheduledProxy(p) {
		http.Error(w, "프록시에는 시작·종료·재시작 버튼을 사용하세요", 400)
		return
	}
	command := strings.ToLower(strings.Fields(q.Command)[0])
	command = strings.TrimPrefix(command, "/")
	if _, name, namespaced := strings.Cut(command, ":"); namespaced {
		command = name
	}
	if command == "stop" || command == "restart" || command == "shutdown" || command == "end" {
		http.Error(w, "종료·재시작 버튼을 사용하세요", 400)
		return
	}
	if !beginInstanceOperation(p.ID, "command") {
		http.Error(w, "작업이 진행 중입니다", 409)
		return
	}
	defer endInstanceOperation(p.ID, nil)
	instanceRuntimeMu.Lock()
	proc := instanceRuntimeLocked(p.ID).process
	instanceRuntimeMu.Unlock()
	if !instanceProcessAlive(proc) {
		http.Error(w, "GSC에서 실행한 서버의 콘솔만 사용할 수 있습니다", 409)
		return
	}
	proc.writeMu.Lock()
	_, err = io.WriteString(proc.stdin, q.Command+"\n")
	proc.writeMu.Unlock()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true})
}

func apiInstanceLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	p, err := instanceByID(r.URL.Query().Get("id"))
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	instanceRuntimeMu.Lock()
	b := append([]byte(nil), instanceRuntimeLocked(p.ID).log...)
	instanceRuntimeMu.Unlock()
	if len(b) == 0 {
		b = instanceRecentLog(filepath.Join(p.Dir, "logs", "latest.log"))
	}
	writeJSON(w, map[string]any{"text": strings.ToValidUTF8(string(bytes.TrimSpace(b)), "�")})
}

func instanceRecentLog(path string) []byte {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil
	}
	if st.Size() > 128<<10 {
		_, _ = f.Seek(-(128 << 10), io.SeekEnd)
	}
	b, _ := io.ReadAll(io.LimitReader(f, 128<<10))
	return b
}

// Host shutdown must not silently abandon a newly managed JVM or its stdin.
// The original external Velocity ownership remains unchanged.
func managedInstanceShutdownBlock() error {
	// apiShutdown claims shuttingDown before calling this guard. Check every
	// runtime entry first, including work whose catalog entry is not visible yet.
	// beginInstanceOperation uses this same mutex and refuses new work once the
	// flag is set, so no start can slip between this snapshot and catalog reads.
	instanceRuntimeMu.Lock()
	for id, state := range instanceRuntimes {
		if state.busy {
			instanceRuntimeMu.Unlock()
			return fmt.Errorf("%s 작업이 진행 중입니다. 완료 후 Host를 종료하세요", id)
		}
		if instanceProcessAlive(state.process) {
			instanceRuntimeMu.Unlock()
			return fmt.Errorf("%s 서버를 먼저 정상 종료하세요", id)
		}
	}
	instanceRuntimeMu.Unlock()
	profiles, err := listManagedInstances()
	if err != nil {
		return err
	}
	for _, p := range profiles {
		if !isScheduledProxy(p) && instancePortOpen(p.JavaPort) {
			return fmt.Errorf("%s 서버를 먼저 정상 종료하세요", p.Name)
		}
		if blocked, reason := instanceReceiptBlocks(p); blocked {
			return fmt.Errorf("%s: %s", p.Name, reason)
		}
	}
	return nil
}
