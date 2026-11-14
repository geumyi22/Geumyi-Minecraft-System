//go:build windows

package main

import (
	"errors"
	"fmt"
	"syscall"
)

func instanceProcessIdentity(pid int) (bool, string, error) {
	p, err := watchPID(pid)
	if err != nil {
		if errors.Is(err, syscall.Errno(87)) {
			return false, "", nil
		}
		return false, "", err
	}
	defer p.close()
	if !p.alive() {
		return false, "", nil
	}
	var created, exited, kernel, user syscall.Filetime
	if err = syscall.GetProcessTimes(p.handle, &created, &exited, &kernel, &user); err != nil {
		return true, "", err
	}
	return true, fmt.Sprintf("%08x%08x", created.HighDateTime, created.LowDateTime), nil
}
