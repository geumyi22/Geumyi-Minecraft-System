package javaruntime

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

type Runtime struct{ Executable, Home, Version string }

var cacheMu sync.Mutex
var cache = map[string]Runtime{}

// Resolve probes Java instead of deriving JAVA_HOME from an Oracle javapath shim.
func Resolve(preferred string) (Runtime, error) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	if r, ok := cache[preferred]; ok {
		if _, e := os.Stat(r.Executable); e == nil {
			return r, nil
		}
	}
	name := "java"
	if runtime.GOOS == "windows" {
		name = "java.exe"
	}
	candidates := []string{preferred, filepath.Join(os.Getenv("JAVA_HOME"), "bin", name)}
	if p, e := exec.LookPath(name); e == nil {
		candidates = append(candidates, p)
	}
	var found []string
	for _, vendor := range []string{"Java", "Eclipse Adoptium", "Microsoft", "BellSoft", "Zulu", "Amazon Corretto"} {
		root := os.Getenv("ProgramFiles")
		if root == "" {
			continue
		}
		m, _ := filepath.Glob(filepath.Join(root, vendor, "*", "bin", "java.exe"))
		found = append(found, m...)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(found)))
	candidates = append(candidates, found...)
	seen := map[string]bool{}
	var last error
	for _, p := range candidates {
		p = strings.Trim(strings.TrimSpace(p), "\"")
		if p == "" {
			continue
		}
		if strings.EqualFold(filepath.Base(p), "javaw.exe") {
			p = filepath.Join(filepath.Dir(p), "java.exe")
		}
		if resolved, e := filepath.EvalSymlinks(p); e == nil {
			p = resolved
		}
		key := strings.ToLower(p)
		if seen[key] {
			continue
		}
		seen[key] = true
		if !filepath.IsAbs(p) {
			continue
		}
		if _, e := os.Stat(p); e != nil {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		c := exec.CommandContext(ctx, p, "-XshowSettings:properties", "-version")
		hide(c)
		out, e := c.CombinedOutput()
		cancel()
		if e != nil {
			last = fmt.Errorf("Java 확인 실패 (%s): %w", p, e)
			continue
		}
		r, e := parseProperties(string(out))
		if e != nil {
			last = e
			continue
		}
		r.Executable = filepath.Join(r.Home, "bin", name)
		if _, e = os.Stat(r.Executable); e != nil {
			last = fmt.Errorf("실제 Java 실행 파일 없음: %s", r.Executable)
			continue
		}
		cache[preferred] = r
		return r, nil
	}
	if last == nil {
		last = errors.New("실행 가능한 Java를 찾지 못했습니다. Java 설치 및 server.json의 agent.java_path를 확인하세요")
	}
	return Runtime{}, last
}
func parseProperties(output string) (Runtime, error) {
	var r Runtime
	for _, line := range strings.Split(output, "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch strings.TrimSpace(k) {
		case "java.home":
			r.Home = strings.TrimSpace(v)
		case "java.version":
			r.Version = strings.TrimSpace(v)
		}
	}
	if r.Home == "" {
		return r, errors.New("Java의 java.home 정보를 확인하지 못했습니다")
	}
	return r, nil
}
