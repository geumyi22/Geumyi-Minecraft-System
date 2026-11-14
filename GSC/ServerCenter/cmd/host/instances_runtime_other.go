//go:build !windows

package main

import (
	"errors"
	"syscall"
)

func instanceProcessIdentity(pid int) (bool, string, error) {
	err := syscall.Kill(pid, 0)
	if errors.Is(err, syscall.ESRCH) {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}
	return true, "", nil
}
