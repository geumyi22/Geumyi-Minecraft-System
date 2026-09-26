//go:build windows

package main

import (
	"bytes"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Runs a real cmd.exe on Windows; this cannot be substituted with a source-text check.
func TestWindowsBatchLaunchFromSystem32UsesServerDirectory(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "야생 Server & %UNCHANGED%")
	os.MkdirAll(dir, 0755)
	batch := filepath.Join(dir, "start.bat")
	os.WriteFile(filepath.Join(dir, "marker.txt"), []byte("SERVER-DIRECTORY-OK"), 0600)
	os.WriteFile(batch, []byte("@echo off\r\ntype marker.txt\r\necho STDERR-OK 1>&2\r\nexit /b 17\r\n"), 0600)
	line, actual, e := resolveLaunch("start.bat", dir)
	if e != nil {
		t.Fatal(e)
	}
	c := shellCommand(line)
	c.Dir = dir
	c.Env = setEnvValue(os.Environ(), "GSC_LAUNCH_FILE", actual)
	var stdout, stderr bytes.Buffer
	c.Stdout = &stdout
	c.Stderr = &stderr
	e = c.Run()
	if e == nil || c.ProcessState.ExitCode() != 17 {
		t.Fatalf("batch exit code lost: %v %s %s", e, &stdout, &stderr)
	}
	if !strings.Contains(stdout.String(), "SERVER-DIRECTORY-OK") || !strings.Contains(stderr.String(), "STDERR-OK") {
		t.Fatalf("wrong cwd or redirection: %s %s", &stdout, &stderr)
	}
}
func TestWindowsListeningProcessLookup(t *testing.T) {
	for _, network := range []string{"tcp4", "tcp6"} {
		t.Run(network, func(t *testing.T) {
			host := "127.0.0.1:0"
			if network == "tcp6" {
				host = "[::1]:0"
			}
			ln, e := net.Listen(network, host)
			if e != nil {
				t.Skip(e)
			}
			defer ln.Close()
			pid, e := portPID(ln.Addr().(*net.TCPAddr).Port)
			if e != nil || pid != os.Getpid() {
				t.Fatalf("wrong owner: %d %v", pid, e)
			}
			p, e := watchPID(pid)
			if e != nil {
				t.Fatal(e)
			}
			defer p.close()
			if !p.alive() {
				t.Fatal("current process not alive")
			}
		})
	}
}
