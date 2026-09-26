//go:build !windows

package main

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
)

func hideProcess(c *exec.Cmd)            {}
func shellCommand(line string) *exec.Cmd { return exec.Command("sh", "-c", line) }
func killProcessTree(pid int) error      { return errors.New("Windows only") }

type processWatch struct{ pid int }

func watchPID(pid int) (*processWatch, error) { return &processWatch{pid}, nil }
func (p *processWatch) alive() bool {
	if p == nil {
		return false
	}
	x, e := os.FindProcess(p.pid)
	return e == nil && x.Signal(syscall.Signal(0)) == nil
}
func (p *processWatch) close() {}
func (p *processWatch) pidValue() int {
	if p == nil {
		return 0
	}
	return p.pid
}
func portPID(port int) (int, error)              { return 0, errors.New("Windows only") }
func nativeTCPListener(port int) bool            { return false }
func nativeUDPListener(port int) bool            { return false }
func nativeJavaStats(port int) (JavaStats, bool) { return JavaStats{}, false }
func nativeHostStats() (HostStats, bool)         { return HostStats{}, false }
