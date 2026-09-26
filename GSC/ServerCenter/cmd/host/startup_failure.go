package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type StartupFailure struct {
	Code   string
	Title  string
	Hint   string
	Source string
	Line   string
}

type startupLogCursor struct {
	offsets map[string]int64
	tails   map[string]string
}

type startupFailurePattern struct {
	needle string
	code   string
	title  string
	hint   string
}

var startupFailurePatterns = []startupFailurePattern{
	{"failed to load datapacks, can't proceed with server load", "datapack-load", "데이터팩 로딩 실패", "world/datapacks의 구버전/손상된 데이터팩을 확인하거나 26.3 호환판으로 교체하세요."},
	{"failed to load registries due to errors", "registry-load", "레지스트리 로딩 실패", "데이터팩의 advancement/loot table/predicate 등 26.3 비호환 문법을 확인하세요."},
	{"you need to agree to the eula", "eula", "EULA 동의 필요", "eula.txt에서 eula=true 설정을 확인하세요."},
	{"failed to bind to port", "port-bind", "서버 포트 사용 중", "같은 Java 포트를 사용하는 다른 서버 프로세스가 있는지 확인하세요."},
	{"perhaps a server is already running on that port", "port-bind", "서버 포트 사용 중", "같은 Java 포트를 사용하는 다른 서버 프로세스가 있는지 확인하세요."},
	{"unsupportedclassversionerror", "java-version", "Java 버전 불일치", "현재 Paper가 요구하는 Java 버전과 start.bat의 Java 경로를 확인하세요."},
	{"could not create the java virtual machine", "java-vm", "Java VM 시작 실패", "start.bat의 Java 옵션과 메모리 설정, Java 설치 상태를 확인하세요."},
	{"could not reserve enough space for object heap", "java-memory", "Java 메모리 할당 실패", "start.bat의 -Xmx/-Xms 값을 줄이거나 사용 가능한 RAM을 확인하세요."},
	{"unable to access jarfile", "jar-missing", "서버 JAR 접근 실패", "start.bat의 JAR 파일명과 서버 폴더의 실제 paper.jar 경로를 확인하세요."},
	{"invalid or corrupt jarfile", "jar-corrupt", "서버 JAR 손상", "Paper JAR을 다시 받아 교체하세요."},
	{"failed to start the minecraft server", "minecraft-start", "Minecraft 서버 시작 실패", "실행 로그와 latest.log의 바로 위 원인 메시지를 확인하세요."},
	{"java.lang.outofmemoryerror", "out-of-memory", "Java 메모리 부족", "서버 RAM 설정과 다른 프로세스의 메모리 사용량을 확인하세요."},
}

func newStartupLogCursor(s ServerConfig) *startupLogCursor {
	c := &startupLogCursor{offsets: map[string]int64{}, tails: map[string]string{}}
	for _, p := range startupLogPaths(s) {
		if st, err := os.Stat(p); err == nil {
			c.offsets[p] = st.Size()
		} else {
			c.offsets[p] = 0
		}
	}
	return c
}

func startupLogPaths(s ServerConfig) []string {
	out := []string{launcherLogPath(s.ID)}
	if dir := resolveServerDir(s); dir != "" {
		out = append(out, filepath.Join(dir, "logs", "latest.log"))
	}
	return out
}

func (c *startupLogCursor) detect() *StartupFailure {
	if c == nil {
		return nil
	}
	for path, offset := range c.offsets {
		b, next, err := readLogGrowth(path, offset, 2<<20)
		if err != nil {
			continue
		}
		c.offsets[path] = next
		if len(b) == 0 {
			continue
		}
		combined := c.tails[path] + string(b)
		if len(combined) > 2048 {
			c.tails[path] = combined[len(combined)-2048:]
		} else {
			c.tails[path] = combined
		}
		if f := classifyStartupFailure(combined); f != nil {
			f.Source = path
			return f
		}
	}
	return nil
}

func readLogGrowth(path string, offset int64, maxBytes int64) ([]byte, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, offset, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, offset, err
	}
	size := st.Size()
	if size < offset {
		offset = 0 // latest.log was recreated/truncated for this boot.
	}
	if size <= offset {
		return nil, size, nil
	}
	start := offset
	if maxBytes > 0 && size-start > maxBytes {
		start = size - maxBytes
	}
	if _, err = f.Seek(start, 0); err != nil {
		return nil, offset, err
	}
	b := make([]byte, size-start)
	n, err := f.Read(b)
	if err != nil && n == 0 {
		return nil, offset, err
	}
	return b[:n], size, nil
}

func classifyStartupFailure(text string) *StartupFailure {
	lines := strings.Split(strings.ReplaceAll(text, "\r", ""), "\n")
	for _, line := range lines {
		low := strings.ToLower(line)
		for _, p := range startupFailurePatterns {
			if strings.Contains(low, p.needle) {
				cleaned := strings.TrimSpace(line)
				if len(cleaned) > 500 {
					cleaned = cleaned[:500]
				}
				return &StartupFailure{Code: p.code, Title: p.title, Hint: p.hint, Line: cleaned}
			}
		}
	}
	return nil
}

func applyStartupFailure(id string, f *StartupFailure) {
	if f == nil {
		return
	}
	runtimeMu.Lock()
	v := launchStates[id]
	v.Phase = "startup-failed"
	v.Message = "부팅 실패 감지 · 자동 재시작 중지"
	v.Error = f.Title
	v.FailureCode = f.Code
	v.FailureTitle = f.Title
	v.FailureHint = f.Hint
	v.FailureSource = f.Source
	v.FailureLine = f.Line
	v.FailureDetected = time.Now().Format(time.RFC3339)
	v.Updated = time.Now().Format(time.RFC3339)
	v.LogPath = launcherLogPath(id)
	launchStates[id] = v
	runtimeMu.Unlock()
	setDesired(id, false)
	if err := forceStopLauncherTree(id); err != nil {
		// The wrapper may already have exited normally after Minecraft aborted.
		if !strings.Contains(strings.ToLower(err.Error()), "not running") {
			appendLauncherNote(id, "startup failure cleanup: "+err.Error())
		}
	}
	appendLauncherNote(id, fmt.Sprintf("startup failure detected: %s (%s) source=%s line=%s", f.Title, f.Code, f.Source, f.Line))
}

func clearStartupFailure(id string) {
	runtimeMu.Lock()
	v := launchStates[id]
	v.FailureCode = ""
	v.FailureTitle = ""
	v.FailureHint = ""
	v.FailureSource = ""
	v.FailureLine = ""
	v.FailureDetected = ""
	if v.Phase == "startup-failed" {
		v.Phase = "idle"
		v.Message = ""
		v.Error = ""
	}
	launchStates[id] = v
	runtimeMu.Unlock()
}

func appendLauncherNote(id, note string) {
	if err := os.MkdirAll(filepath.Dir(launcherLogPath(id)), 0755); err != nil {
		return
	}
	f, err := os.OpenFile(launcherLogPath(id), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "[%s] GSC: %s\r\n", time.Now().Format(time.RFC3339), note)
}
