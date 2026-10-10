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

 // Regression: a connected client's ephemeral local port appears in Windows
 // TCP owner tables but is NOT a listening server. Never hand its PID to
 // rememberServerProcess or forceStopServer as if it owned a Java listener.
func TestWindowsPortPIDRejectsEstablishedClientPort(t *testing.T) {
	for _, tc := range []struct{network, address string}{
		{"tcp4", "127.0.0.1:0"},
		{"tcp6", "[::1]:0"},
	} {
		t.Run(tc.network, func(t *testing.T) {
			ln, err := net.Listen(tc.network, tc.address)
			if err != nil { t.Skipf("loopback listener unsupported: %v", err) }
			defer ln.Close()
			client, err := net.Dial(tc.network, ln.Addr().String())
			if err != nil { t.Fatal(err) }
			defer client.Close()
			accepted, err := ln.Accept()
			if err != nil { t.Fatal(err) }
			defer accepted.Close()
			local := client.LocalAddr().(*net.TCPAddr).Port
			if local == ln.Addr().(*net.TCPAddr).Port {
				t.Fatal("unexpected same client ephemeral and server listener port")
			}
			if pid, err := portPID(local); err == nil || pid != 0 {
				t.Fatalf("non-listener connected client port %d attributed to pid %d: %v", local, pid, err)
			}
		})
	}
}

func TestWindowsPortPIDRejectsOutOfRangePort(t *testing.T) {
	for _, port := range []int{-1, 0} {
		if pid, err := portPID(port); err == nil || pid != 0 {
			t.Fatalf("invalid port %d attributed to pid %d: %v", port, pid, err)
		}
	}
}
